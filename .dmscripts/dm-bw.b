#!/usr/bin/env bash

configHome="${XDG_CONFIG_HOME:-${HOME}/.config}/dmscripts" #^
configFile="${configHome}/bw.json"
self=$(basename "${0##/*/}")
source /home/jpszc/.cache/bwsession

if [ -e "$configFile" ]; then
    copyCmds=$(jq -r ".copyCmds" "$configFile")
    dmenuOpts=$(jq -r ".dmenuOpts" "$configFile")
    editCmd=$(jq -r ".editCmd" "$configFile")
    passwordGenCmd=$(jq -r ".passwordGenCmd" "$configFile")
    sessionKeyFile=$(jq -r ".sessionKeyFile" "$configFile"); fi

if [ -z "$copyCmds" ] || [ "$copyCmds" = "null" ]; then
    copyCmds='
    {
        "login": {
            ".login.username": [
                "echo \"$value\" | xclip -i -selection clipboard"
            ],
            ".login.password": [
                "echo \"$value\" | xclip -i -selection primary"
            ]
        },
        "secureNote": {
	    ".notes": [
                 "echo \"$value\" | xclip -i -selection primary"
            ]
        },
        "card": {},
        "identity": {}
    }'; fi
if [ -z "$dmenuOpts" ] || [ "$dmenuOpts" = "null" ]; then
    dmenuOpts="-i -l 10"; fi
if [ -z "$editCmd" ] || [ "$editCmd" = "null" ]; then
    editCmd="xterm -e nano"; fi
[ "$passwordGenCmd" = "null" ] &&
    unset passwordGenCmd
[ "$sessionKeyFile" = "null" ] &&
    unset sessionKeyFile #$

bwStatus=$(bw status | jq -r '.status') #^
case "$bwStatus" in
    unlocked)   : ;;
    *)  case "$bwStatus" in
            unauthenticated)
                notify-send "$self" "Unauthenticated session. Acquiring new session key." &
                login=$(yad --form \
                    --field="Email" "" \
                    --field="Password":H "" \
                    --separator="\n" |
                        grep -v "^$")
                sessionKey=$(bw login \
                    "$(echo "$login" | sed -n "1p")" \
                    "$(echo "$login" | sed -n "2p")" \
                    --raw) ;;
            locked)
                notify-send "$self" "Session locked. Acquiring new session key." &
                password=$(yad \
                    --title "Password" \
                    --entry \
                    --hide-text)
                sessionKey=$(bw unlock "$password" --raw) ;;
            *)  notify-send "$self" "Failed to unlock session." &
                exit 1 ;;
        esac

        # output session key to file
        if [ -n "$sessionKeyFile" ]; then
            printf 'export BW_SESSION="%s"' \
                "$sessionKey" > "$sessionKeyFile"
        fi

        # confirm login
        export BW_SESSION=$sessionKey
        case $(bw status | jq -r '.status') in
            unlocked) : ;;
            *)  notify-send "$self" "Failed to unlock session." &
                exit 1 ;;
        esac ;;
esac #$
database=$(bw list items)
sepStr="=" #^
sep () {
    i=0
    while [ $i -le 500 ]; do
        printf "%s" "$sepStr"
        i=$(( i + 1 ))
    done
    printf "\n"
}

main_list () {
    echo "create"
    echo "logout"
    echo "sync"
    sep
    echo $database | jq -r '.[] | "\(.name) | \(.login.username) | \(.id)"'
    sep
    echo "run Bitwarden Electron"
}

item_list () {
    echo "copy"
    echo "edit"
    echo "delete"
}

create_list () {
    echo "login"
    echo "secure note"
    echo "card"
    echo "identity"
} #$

createHelper () { #^
    # create helper
    # $1: props
    # $2: form
    i=0
    n=$(echo "$props" | awk '{print NF}')
    while [ $i -lt $n ]; do
        i=$((i + 1))
        prop=$(printf "%s" "$1" | awk "{print \$${i}}")
        value=$(printf "%s" "$2" | sed -n "${i}p")
        case "$value" in
            "")     newItem=$(echo "$newItem" | jq -c "${prop} = null") ;;
            TRUE)   newItem=$(echo "$newItem" | jq -c "${prop} = true") ;;
            FALSE)  newItem=$(echo "$newItem" | jq -c "${prop} = false") ;;
            *)      newItem=$(echo "$newItem" | jq -c "${prop} = \"$value\"") ;;
        esac
    done
}

create () {
    # create a vault item
    # $1: item type

    newItem=$(bw get template item)
    template=$(bw get template item."${1}")
    newItem=$(echo "$newItem" | jq -c ".${1} = ${template}")

    case "$1" in
        login) #^
            uri=$(bw get template item.login.uri)
            [ -n "$passwordGenCmd" ] &&
                password=$(eval "$passwordGenCmd")
            newItem=$(echo "$newItem" | jq -c ".login.uris = [${uri}]")
            props=".name .login.username .login.password .login.uris[0].uri .folderId .favorite .notes"
            form=$(yad --form \
                --field="Name" "" \
                --field="Username" "" \
                --field="Password":H "${password:-""}" \
                --field="URI" "" \
                --field="Folder" "" \
                --field="Favorite":CHK "false" \
                --field="Notes":TXT "" \
                --separator="\n")
            createHelper "$props" "$form"
            ;; #$

        secureNote) #^
            newItem=$(echo "$newItem" | jq -c ".type = 2")
            props=".name .folderId .favorite .notes"
            form=$(yad --form \
                --field="Name" "" \
                --field="Folder" "" \
                --field="Favorite":CHK "false" \
                --field="Notes":TXT "" \
                --separator="\n")
            createHelper "$props" "$form"
            ;; #$

        card) #^
            newItem=$(echo "$newItem" | jq -c '.type = 3')
            props=".name .card.cardholderName .card.number .card.brand .card.expMonth .card.expYear .card.code .folderId .favorite .notes"
            form=$(yad --form \
                --field="Name" "" \
                --field="Cardholder Name" "" \
                --field="Number":H "" \
                --field="Brand":CBE "Visa!Mastercard!American Express!Discover!Diners Club!JCB!Maestro!UnionPay" \
                --field="Expiration Month":NUM "!1..12" \
                --field="Expiration Year":NUM "!1900..9999" \
                --field="Security Code":NUM "!100..999" \
                --field="Folder" "" \
                --field="Favorite":CHK "false" \
                --field="Notes":TXT "" \
                --separator="\n")
            createHelper "$props" "$form"
            ;; #$

        identity) #^
            newItem=$(echo "$newItem" | jq -c '.type = 4')
            props=".name .identity.title .identity.firstName .identity.middleName .identity.lastName .identity.username .identity.company .identity.ssn .identity.passportNumber .identity.licenseNumber .identity.email .identity.address1 .identity.address2 .identity.address3 .identity.city .identity.state .identity.postalCode .identity.country .favorite .folder .notes"
            form=$(yad --form \
                --field="Name" "" \
                --field="Title":CB "Mr!Mrs!Ms!Dr" \
                --field="First Name" "" \
                --field="Middle Name" "" \
                --field="Last Name" "" \
                --field="Username" "" \
                --field="Company" "" \
                --field="Social Security Number" "" \
                --field="Passport Number" "" \
                --field="License Number" "" \
                --field="Email" "" \
                --field="Address 1" "" \
                --field="Address 2" "" \
                --field="Address 3" "" \
                --field="City/Town" "" \
                --field="State/Province" "" \
                --field="Zip/Postal Code" "" \
                --field="Country" "" \
                --field="Favorite":CHK "false" \
                --field="Folder" "" \
                --field="Notes":TXT "" \
                --separator="\n")
            createHelper "$props" "$form"
            ;; #$

        *) kill 0 ;;
    esac

    echo "$newItem" |
        bw encode |
        bw create item &&
            notify-send "$self" "Creation successful." ||
            notify-send "$self" "Creation failed." &
} #$

edit () { #^
    # edit a vault item
    # $1: item json
    # $2: item id

    # create secure temporary files for editing vault items
    tmpDir=$(mktemp -d /tmp/dmenu_bw.XXXXXX)
    chmod 700 "$tmpDir"
    newItem=$(mktemp "${tmpDir}/dmenu_bw.json.XXXXXX")
    chmod 600 "$newItem"
    echo "$1" | jq > "$newItem"

    # open item with editor command
    if ! $editCmd "$newItem"; then
        notify-send "$self" "Failed to run ${editCmd}." &
        kill 0
    fi

    # do not accept invalid JSON
    if ! jq "." "$newItem" 1>/dev/null 2>&1; then
        notify-send "$self" "Cannot parse invalid JSON." &
        kill 0
    fi

    bw encode < "$newItem" | bw edit item "$2" &&
        notify-send "$self" "Edit successful." ||
        notify-send "$self" "Edit failed." &

    # delete temporary files
    rm -rf "$tmpDir" 1>/dev/null 2>&1
} #$

chosen=$(main_list | dmenu ${dmenuOpts}); [ -n "$chosen" ] || exit 1
case "$chosen" in
    create)     chosen=$(create_list | dmenu ${dmenuOpts}); [ -n "$chosen" ] || exit 1
                case "$chosen" in
                    login)          create login ;;
                    "secure note")  create secureNote ;;
                    card)           create card ;;
                    identity)       create identity ;;
                esac ;;
    logout)     bw logout &&
                    notify-send "$self" "Logout successful." ||
                    notify-send "$self" "Logout failed." & ;;
    sync)       bw sync -f &&
                    notify-send "$self" "Sync successful." ||
                    notify-send "$self" "Sync failed." & ;;
    "run Bitwarden Electron") bitwarden ;;
    ${sepStr}*) exit 1 ;;
    *)          name=$(echo "$chosen" | cut -d '|' -f 1 | tr -d '[:space:]') # use awk
                id=$(echo "$chosen" | cut -d '|' -f 3 | tr -d '[:space:]')
                item=$(echo $database | jq -c ".[] | select(.id == \"$id\")")
                itemType=$(echo "$item" | jq -r ".type")
                case "$itemType" in
                    1) itemType=".login" ;;
                    2) itemType=".secureNote" ;;
                    3) itemType=".card" ;;
                    4) itemType=".identity" ;;
                esac
                chosen=$(item_list | dmenu ${dmenuOpts}); [ -n "$chosen" ] || exit 1
                case "$chosen" in
                    copy)   keys=$(echo "$copyCmds" | jq -r "${itemType} | keys[]")
                            unset fail
                            for key in $keys; do
                                value=$(echo "$item" | jq -r "${key}")
                                cmds=$(echo "$copyCmds" | jq -r "${itemType}[\"${key}\"][]")
                                for cmd in "$cmds"; do
                                    if ! eval "$cmd"; then
                                        notify-send "$self" "Copy command failed: \"$cmd\"" &
                                        fail=t; fi
                                done
                            done
                            [ -z "$fail" ] &&
                                notify-send "$self" "$name copied successfully." & ;;
                    delete) bw delete item "$id" &&
                                notify-send "$self" "Deletion successful." ||
                                notify-send "$self" "Deletion failed." & ;;
                    edit)   edit "$item" "$id" ;;
                esac ;;
esac
