#!/bin/bash

# bash-completion script for https://github.com/JessThrysoee/parallelsvm

# homebrew install:
#  cp parallelsvm-completion.bash `brew --prefix`/etc/bash_completion.d/

_parallelsvm()
{
   local cur prev action

   COMPREPLY=()

   cur="${COMP_WORDS[COMP_CWORD]}"
   prev="${COMP_WORDS[COMP_CWORD-1]}"

   if (( $COMP_CWORD == 1 ))
   then
      COMPREPLY=( $(compgen -W "init up halt suspend resume destroy info status global-status shell box" -- "$cur") )

   elif (( $COMP_CWORD == 2 ))
   then
      case "$prev" in
         halt|suspend|shell)
            local IFS=$'\n'
            # complete running VMs
            COMPREPLY=( $(compgen -W "$(prlctl list -o name | tail -n+2)" -- "$cur" | sed 's/ /\\ /g') )
            unset IFS
            ;;

         up|resume)
            local IFS=$'\n'
            # complete not running VMs
            COMPREPLY=( $(compgen -W "$(comm -23 <(prlctl list -a -o name| tail -n+2| sort) <(prlctl list -o name | tail -n+2| sort))" -- "$cur" | sed 's/ /\\ /g') )
            unset IFS
            ;;

         destroy|info|status)
            local IFS=$'\n'
            # complete all VMs
            COMPREPLY=( $(compgen -W "$(prlctl list -a -o name| tail -n+2)" -- "$cur" | sed 's/ /\\ /g') )
            unset IFS
            ;;

         box)
            COMPREPLY=( $(compgen -W "add list saveas remove rename" -- "$cur") )
            ;;

         *)
            ;;
      esac

   elif (( $COMP_CWORD == 3 ))
   then
      action="${COMP_WORDS[1]}"

      case "$action" in
         halt)
            COMPREPLY=( $(compgen -W "--force" -- "$cur") )
            ;;

         box)
            case "$prev" in
               remove|rename)
                  local IFS=$'\n'
                  COMPREPLY=( $(compgen -W "$(parallelsvm box list)" -- "$cur" | sed 's/ /\\ /g') )
                  unset IFS
                  ;;
               *)
                  ;;
            esac
            ;;

         *)
            ;;
      esac
   fi

   return 0

}

complete -F _parallelsvm parallelsvm

