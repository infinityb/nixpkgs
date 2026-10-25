source "$NIX_ATTRS_SH_FILE"
source $mirrorsFile

# Normalize `curlOpts` as a string.
# If defined as a list (deprecated), it would be a bash array.
if [[ "$(declare -p curlOpts 2&>/dev/null || true)" =~ ^"declare -a" ]]; then
    unset _temp
    _temp="${curlOpts[*]}"
    unset curlOpts
    curlOpts=$_temp
    unset _temp
fi

curlVersion=$(curl -V | head -1 | cut -d' ' -f2)

# Curl flags to handle redirects, not use EPSV, handle cookies for
# servers to need them during redirects, and work on SSL without a
# certificate (this isn't a security problem because we check the
# cryptographic hash of the output anyway).
curl=(
    curl
    --location
    --max-redirs 20
    --retry 3
    --retry-all-errors
    --disable-epsv
    --cookie-jar cookies
    --user-agent "curl/$curlVersion Nixpkgs/$nixpkgsVersion"
)

if ! [ -f "$SSL_CERT_FILE" ]; then
    curl+=(--insecure)
fi

# NOTE:
# `netrcPhase` should not attempt to access builder.sh implementation details (e.g., the `${curl[@]}` array),
# The implementation detail could change in any Nixpkgs revision, including backports.
if [[ -n "${netrcPhase-}" ]]; then
    runPhase netrcPhase
    curl+=(--netrc-file "$PWD/netrc")
fi

curl+=(
    "${curlOptsList[@]}"
    $curlOpts
    $NIX_CURL_FLAGS
)

# curl (>= 8.12) rejects --continue-at combined with --range instead of
# silently ignoring one of them (https://github.com/curl/curl/issues/15646),
# and a byte range request cannot be resumed anyway. So only request a resumed
# transfer when the caller did not ask for a range.
read -r -a curlOptWords <<< "$curlOpts $NIX_CURL_FLAGS" || true
resumeOpts=(-C -)
for opt in "${curlOptsList[@]}" "${curlOptWords[@]}"; do
    case "$opt" in
        -r* | --range*)
            resumeOpts=( )
            break
            ;;
    esac
done

downloadedFile="$out"
if [ -n "$downloadToTemp" ]; then downloadedFile="$TMPDIR/file"; fi

tryDownload() {
    local url="$1"
    local target="$2"
    echo
    echo "trying $url"
    local curlexit=18;

    success=

    # if we get error code 18, resume partial download
    while [ $curlexit -eq 18 ]; do
       # keep this inside an if statement, since on failure it doesn't abort the script
       if "${curl[@]}" "${resumeOpts[@]}" --fail "$url" --output "$target"; then
          success=1
          break
       else
          curlexit=$?;
       fi
    done
}


finish() {
    local skipPostFetch="$1"

    set +o noglob

    if [[ $executable == "1" ]]; then
      chmod +x $downloadedFile
    fi

    if [ -z "$skipPostFetch" ]; then
        runHook postFetch
    fi

    exit 0
}


# A hashed mirror is laid out as `<mirror>/<algo>/<nix-base32-of-the-digest>',
# e.g.
#   https://tarballs.nixos.org/sha256/1iig3rq8cch7ly3ikkkby5mnmq8zs28qri0yqnzpbv8avvn4xmzp
# The derivation only carries `outputHash', and fetchurl sets it in SRI form
# (`sha256-<base64>') with no `outputHashAlgo' at all, so neither part of that
# path can be taken from the environment as-is. Everything needed to convert
# the digest is coreutils (base64/od/tr); note that this environment has no
# nix, python or perl on PATH.
nixBase32FromHex () {
    local hex="$1"
    local alphabet='0123456789abcdfghijklmnpqrsvwxyz'
    local nbytes=$(( ${#hex} / 2 ))
    local ndigits=$(( (nbytes * 8 + 4) / 5 ))
    local out=''
    local n b i j c byte next

    # Nix renders a digest as a little-endian base-32 number: digit n covers
    # bits 5n..5n+4 (each byte counted from its least significant bit) and the
    # most significant digit is emitted first.
    for (( n = ndigits - 1; n >= 0; n -= 1 )); do
        b=$(( n * 5 ))
        i=$(( b / 8 ))
        j=$(( b % 8 ))
        byte=$(( 16#${hex:i * 2:2} ))
        c=$(( byte >> j ))
        if (( i + 1 < nbytes )); then
            next=$(( 16#${hex:i * 2 + 2:2} ))
            c=$(( c | next << (8 - j) ))
        fi
        out="${out}${alphabet:c & 31:1}"
    done

    printf '%s' "$out"
}

# Echoes `<algo>/<nix-base32>' for this derivation's fixed-output hash, and
# fails if there is nothing sensible to build a path from.
hashedMirrorPath () {
    local hash="${outputHash:-}"
    local algo="${outputHashAlgo:-}"
    local b64=''
    local hex=''

    if [[ "$hash" =~ ^([a-z0-9]+)-([A-Za-z0-9+/]+)=*$ ]]; then
        # SRI, as fetchurl sets it: `sha256-99dO7N4K7XW/xR7E…'. The algorithm
        # comes from the prefix and the base64 padding is optional.
        algo="${BASH_REMATCH[1]}"
        b64="${BASH_REMATCH[2]}"
        while [ $(( ${#b64} % 4 )) -ne 0 ]; do b64="${b64}="; done
        hex="$(printf '%s' "$b64" | base64 -d 2>/dev/null | od -An -v -tx1 | tr -d ' \n')"
        case "$hex" in
            '') return 1 ;;
            *[!0-9a-fA-F]*) return 1 ;;
        esac
        printf '%s/%s' "$algo" "$(nixBase32FromHex "${hex,,}")"
        return
    fi

    if [ -z "$algo" ]; then
        return 1
    fi

    # Legacy hashes. `algo:hex' or bare hex plus outputHashAlgo still have to
    # be rendered; anything else is already in the form the mirror uses (a
    # nix-base32 digest, which is what fetchurl used to put in `outputHash'),
    # so keep using it verbatim.
    hex="${hash#*:}"
    case "$hex" in
        '') return 1 ;;
        *[!0-9a-fA-F]*) printf '%s/%s' "$algo" "$hex" ;;
        *) printf '%s/%s' "$algo" "$(nixBase32FromHex "${hex,,}")" ;;
    esac
}


tryHashedMirrors() {
    if test -n "$NIX_HASHED_MIRRORS"; then
        hashedMirrors="$NIX_HASHED_MIRRORS"
    fi

    local mirrorPath
    if ! mirrorPath="$(hashedMirrorPath)"; then
        echo "warning: cannot derive a hashed-mirror path from outputHash \`$outputHash', not trying hashed mirrors"
        return 0
    fi

    for mirror in $hashedMirrors; do
        url="$mirror/$mirrorPath"
        if "${curl[@]}" --retry 0 --connect-timeout "${NIX_CONNECT_TIMEOUT:-15}" \
            --fail --silent --show-error --head "$url" \
            --write-out "%{http_code}" --output /dev/null > code 2> log; then
            # Directly download to $out, because postFetch doesn't need to run,
            # since hashed mirrors provide pre-built derivation outputs.
            tryDownload "$url" "$out"

            # We skip postFetch here, because hashed-mirrors are
            # already content addressed. So if $outputHash is in the
            # hashed-mirror, changes from ‘postFetch’ would already be
            # made. So, running postFetch will end up applying the
            # change /again/, which we don’t want.
            if test -n "$success"; then finish skipPostFetch; fi
        else
            # Be quiet about 404 errors, which we interpret as the file
            # not being present on this particular mirror. Everything else
            # gets a line in the log so a broken mirror isn't invisible.
            if test "$(cat code)" != 404; then
                echo "error checking the existence of $url (HTTP $(cat code)):"
                cat log
            fi
        fi
    done
}


# URL list may contain ?. No glob expansion for that, please
set -o noglob

resolvedUrls=()
for url in "${urls[@]}"; do
    if test "${url:0:9}" != "mirror://"; then
        resolvedUrls+=("$url")
    else
        url2="${url:9}"; echo "${url2/\// }" > split; read site fileName < split
        #varName="mirror_$site"
        varName="$site" # !!! danger of name clash, fix this
        if test -z "${!varName}"; then
            echo "warning: unknown mirror:// site \`$site'"
        else
            mirrors=${!varName}

            # Allow command-line override by setting NIX_MIRRORS_$site.
            varName="NIX_MIRRORS_$site"
            if test -n "${!varName}"; then mirrors="${!varName}"; fi

            for url3 in $mirrors; do
                resolvedUrls+=("$url3$fileName");
            done
        fi
    fi
done

# Restore globbing settings
set +o noglob

if test -n "$showURLs"; then
    echo "${resolvedUrls[*]}" > $out
    exit 0
fi

if test -n "$preferHashedMirrors"; then
    tryHashedMirrors
fi

# URL list may contain ?. No glob expansion for that, please
set -o noglob

success=
for url in "${resolvedUrls[@]}"; do
    if [ -z "$postFetch" ]; then
       case "$url" in
           https://github.com/*/archive/*)
               echo "warning: archives from GitHub revisions should use fetchFromGitHub"
               ;;
           https://gitlab.com/*/-/archive/*)
               echo "warning: archives from GitLab revisions should use fetchFromGitLab"
               ;;
       esac
    fi
    tryDownload "$url" "$downloadedFile"
    if test -n "$success"; then finish; fi
done

# Restore globbing settings
set +o noglob

if test -z "$preferHashedMirrors"; then
    tryHashedMirrors
fi


echo "error: cannot download $name from any mirror"
exit 1
