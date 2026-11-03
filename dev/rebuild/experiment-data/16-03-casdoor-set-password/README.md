# Casdoor: changing a password with the application's credentials (2026-11-03)

Foundations item 2, T3: can infra/iam-casdoor change a user's password in Casdoor itself (so it knows which of its
sessions made the change and can keep that one), and does Casdoor still check the old password when an application
calls? Casdoor 4.1.0 (`be-casdoor`, casbin/casdoor:4.1.0). `spike.py` makes a throwaway user as the built-in admin,
calls `/api/set-password` with the login application's `clientId`/`clientSecret`, checks with the development
client's password grant, and deletes the user; output in `out.txt`.

- With the application's credentials and a wrong old password: refused ("password or code is incorrect, you have 4
  remaining chances": the attempt counts toward Casdoor's lockout).
- With the right old password: changed; the old password no longer works, the new one does.
- Without any credentials: refused ("Please login first").

Casdoor's source (controllers/user.go `SetPassword`, read through context7 on 2026-11-03) also sets the user's
`LastChangePasswordTime` and expires the user's Casdoor tokens; the identity member's own sessions are not touched,
so it ends them itself. `LastChangePasswordTime` is what a later pull can compare to find changes made in Casdoor's
own pages.
