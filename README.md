# slime-eat

Send text from any buffer to an [eat](https://codeberg.org/akib/emacs-eat)
terminal, vim-slime style. Pick a target eat buffer, then use the `gz`
Evil operator to send motions, lines, or regions.

## Install

With [elpaca](https://github.com/progfolio/elpaca) + `use-package`:

```elisp
(use-package slime-eat
  :elpaca (slime-eat :host github :repo "jam1015/slime-eat")
  :custom
  (slime-eat-modes '(python-mode python-ts-mode
                     ess-r-mode R-mode
                     sh-mode bash-ts-mode))
  :config
  (slime-eat-refresh-hooks))
```

## Keys

The package ships `slime-eat-mode` with an empty keymap. Bind keys in
your own config, e.g.:

```elisp
(with-eval-after-load 'slime-eat
  (evil-define-key '(normal visual) slime-eat-mode-map
    "gz" #'slime-eat-send-op)
  (evil-define-key 'normal slime-eat-mode-map
    "gzz" #'slime-eat-send-line))
```

The first send prompts for a target eat buffer; it's then stored
buffer-locally. Reselect with `M-x slime-eat-select-target`.

## Options

- `slime-eat-modes` — list of major modes to auto-enable in.
- `slime-eat-bracketed-paste` (default `t`) — wrap sends in
  `\e[200~`/`\e[201~`. Set buffer-locally to `nil` for REPLs that
  don't advertise bracketed paste (plain `python`, some shells).

## License

GPL-3.0-or-later.
