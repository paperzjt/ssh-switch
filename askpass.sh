#!/bin/sh
exec /usr/bin/osascript -e 'set promptText to system attribute "GITHUB_KEY_SWITCHER_PASSPHRASE_PROMPT"' \
  -e 'set cancelText to system attribute "GITHUB_KEY_SWITCHER_CANCEL"' \
  -e 'set continueText to system attribute "GITHUB_KEY_SWITCHER_CONTINUE"' \
  -e 'text returned of (display dialog promptText default answer "" with hidden answer buttons {cancelText, continueText} default button continueText)'
