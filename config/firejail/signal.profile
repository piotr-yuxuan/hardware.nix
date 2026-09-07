# Signal Desktop: retain the upstream application-directory whitelist and
# sensitive-state blacklists. File access goes through desktop portals.

# Desktop integration and the restricted HTTP(S) link bridge both use the
# portal.  The bridge is installed through Signal's executable wrapper.
dbus-user.talk org.freedesktop.portal.Desktop

include signal-desktop.profile
