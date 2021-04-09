# YAASS — Yeet's Automatic Arch Setup Scripts

YAASS is a small project that aims to make installing arch & artix linux easier
and straight-forward. It tries not to make too many assumptions on what the user
wants to do with their setup and prompts for input when there is a choice that
needs to be made. However, it provides a set of default settings that work just fine.
It doesn't install any packages besides some that **I** believe is essential like
connman (Network Manager), git, vim, tmux and xorg.

## Usage

You just need to download the yass.sh and run it. Assuming you already have an
installation usb and booted from it of course. If you want to save a few clicks,
you can do:

```sh
bash -C <(https://yigitcolakoglu.com/auto-yass.sh)
```


## Distros Currently Supported

* Arch Linux
* Artix Linux (OpenRC)
