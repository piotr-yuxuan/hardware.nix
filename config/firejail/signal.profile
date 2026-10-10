# Signal Desktop: sandboxed with full access to the current user's home.  The
# upstream profile still blacklists sensitive application state.
whitelist ${HOME}

# Desktop integration and the restricted HTTP(S) link bridge both use the
# portal.  The bridge is installed through Signal's executable wrapper.
dbus-user.talk org.freedesktop.portal.Desktop

include signal-desktop.profile
