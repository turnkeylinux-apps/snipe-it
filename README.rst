Snipe-IT - Open Source Asset Management
=======================================

`Snipe-IT`_ provides a powerful, user friendly assest managment system, which
your team will love to use. It was designed to enable IT departments big or
small to track who has what hardware, when it was purchased, which software
licenses apply to it and what accessories are available, and so on.

Despite it's intended use for IT, many users online state that it is a great
asset management tool for a whole range of alternate scenarios, such as vehicle
management, including maintenance scheduling.

Snipe-IT provides `extensive documentation`_ online, including a thorough
`User Manual`_.

This TurnKey appliance also includes all the standard features in
`TurnKey Core`_, and on top of that:

- SSL support out of the box.
- `Adminer`_ administration frontend for MySQL (MariaDB) (listening on port
  12322 - uses SSL).
- `Postfix`_ MTA (bound to localhost) to allow sending of email.
- Webmin modules for configuring Apache2, PHP, MySQL and Postfix.

Credentials *(passwords set at first boot)*
-------------------------------------------

-  Webmin, SSH, MySQL: username **root**

-  Adminer: username **adminer**

- Snipe-IT: username is email - set at firstboot

.. _Snipe-IT: https://snipeitapp.com
.. _extensive documentation: https://snipe-it.readme.io/docs
.. _User Manual: https://snipe-it.readme.io/docs/overview
.. _TurnKey Core: https://www.turnkeylinux.org/core
.. _Adminer: https://www.adminer.org/
.. _Postfix: https://www.postfix.org/
