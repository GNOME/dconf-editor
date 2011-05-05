
# Check for bash
[ -z "$BASH_VERSION" ] && return

####################################################################################################

__dconf() {
  local choices

  case "${COMP_CWORD}" in
    1)
      choices=$'help \nread \nlist \nwrite \nupdate \nlock \nunlock \nwatch '
      ;;

    2)
      case "${COMP_WORDS[1]}" in
        help)
          choices=$'help \nread \nlist \nwrite \nupdate \nlock \nunlock \nwatch '
          ;;
        list)
          choices="$(dconf _complete / "${COMP_WORDS[2]}")"
          ;;
        read|list|write|lock|unlock|watch)
          choices="$(dconf _complete '' "${COMP_WORDS[2]}")"
          ;;
      esac
      ;;
  esac

  local IFS=$'\n'
  COMPREPLY=($(compgen -W "${choices}" "${COMP_WORDS[$COMP_CWORD]}"))
}

####################################################################################################

complete -o nospace -F __dconf dconf
