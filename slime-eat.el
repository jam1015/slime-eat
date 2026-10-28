;;; slime-eat.el --- Send text to an eat terminal, vim-slime style -*- lexical-binding: t -*-
;;
;; Copyright (C) 2026 Jordan Mandel
;; Author: Jordan Mandel <jordan.mandel@live.com>
;; Created: 2026-10-28
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1") (eat "0.9") (evil "1.15.0"))
;; Keywords: terminals, tools, convenience
;; Homepage: https://github.com/jam1015/slime-eat
;;
;; This file is not part of GNU Emacs.
;;
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.
;;
;;; Commentary:
;;
;; Mimics the vim-slime workflow for Emacs with eat as the terminal.
;; Pick a target eat buffer, then send a motion / line / region to it
;; using Evil's `gz` operator (configurable).  Opt-in per major mode
;; via `slime-eat-modes'.
;;
;;; Code:

(require 'eat)
(require 'evil)

(defgroup slime-eat nil
  "Send text to eat terminal buffers, vim-slime style."
  :group 'eat
  :prefix "slime-eat-")

(defcustom slime-eat-bracketed-paste t
  "Wrap sent text in bracketed-paste escape sequences.
Set buffer-locally to nil for REPLs that do not advertise
bracketed paste (e.g. plain python without ipython)."
  :type 'boolean)

(defcustom slime-eat-modes nil
  "Major modes in which `slime-eat-mode' is automatically enabled.
Call `slime-eat-refresh-hooks' after changing this value to apply."
  :type '(repeat symbol))

(defvar-local slime-eat-target-buffer nil
  "Eat buffer this source buffer sends to.")

(defun slime-eat--target-buffer-p (buf)
  "Non-nil if BUF is a valid slime-eat target."
  (with-current-buffer buf
    (or (bound-and-true-p eat-terminal)
        (derived-mode-p 'eshell-mode))))

(defun slime-eat--eat-buffers ()
  "Return the list of live buffers usable as slime-eat targets.
Includes eat-mode buffers and eshell buffers (which use eat
internally for TUIs via `eat-eshell-mode')."
  (seq-filter #'slime-eat--target-buffer-p (buffer-list)))

(defun slime-eat--annotate (name)
  "Annotation shown next to candidate NAME in `slime-eat-select-target'."
  (when-let* ((buf (get-buffer name))
              ((buffer-live-p buf)))
    (let* ((dir (buffer-local-value 'default-directory buf))
           (proc (get-buffer-process buf))
           (status (if proc (symbol-name (process-status proc)) "no-proc"))
           (cmd (and proc (car (process-command proc)))))
      (format "  [%s%s]  %s"
              status
              (if cmd (concat " " (file-name-nondirectory cmd)) "")
              (abbreviate-file-name (or dir ""))))))

;;;###autoload
(defun slime-eat-select-target (buffer)
  "Pick BUFFER as the eat target for the current buffer."
  (interactive
   (let ((cands (mapcar #'buffer-name (slime-eat--eat-buffers))))
     (unless cands
       (user-error "No eat or eshell buffers running"))
     (list
      (get-buffer
       (let ((completion-extra-properties
              '(:annotation-function slime-eat--annotate)))
         (completing-read "Eat target: " cands nil t))))))
  (setq slime-eat-target-buffer buffer)
  (message "slime-eat target: %s" (buffer-name buffer)))

(defun slime-eat--ensure-target ()
  "Return the current target buffer, prompting if unset or stale."
  (unless (and (buffer-live-p slime-eat-target-buffer)
               (slime-eat--target-buffer-p slime-eat-target-buffer))
    (call-interactively #'slime-eat-select-target))
  slime-eat-target-buffer)

(defun slime-eat--send-to-eat (text)
  "Send TEXT to the current buffer's eat terminal."
  (if slime-eat-bracketed-paste
      (progn
        (eat-term-send-string eat-terminal "\e[200~")
        (eat-term-send-string eat-terminal text)
        (eat-term-send-string eat-terminal "\e[201~")
        (eat-term-send-string eat-terminal "\r"))
    (eat-term-send-string eat-terminal text)
    (unless (string-suffix-p "\n" text)
      (eat-term-send-string eat-terminal "\r"))))

(defun slime-eat--send-to-eshell (text)
  "Send TEXT to an eshell buffer.
If a subprocess is attached (e.g. a REPL running under eshell),
forward TEXT directly to it so eshell does not try to parse it as
a shell command.  Otherwise, insert at the prompt and submit via
`eshell-send-input'."
  (if-let* ((proc (get-buffer-process (current-buffer))))
      (process-send-string
       proc
       (if (string-suffix-p "\n" text) text (concat text "\n")))
    (goto-char (point-max))
    (insert (string-trim-right text "\n"))
    (eshell-send-input)))

(defun slime-eat--eshell-under-eat-p ()
  "Non-nil if the current eshell buffer has eat active for a visual command.
Mirrors the detection used by `eat-eshell-mode' itself."
  (or (bound-and-true-p eat--eshell-semi-char-mode)
      (bound-and-true-p eat--eshell-char-mode)))

(defun slime-eat-send-string (text)
  "Send TEXT to the target buffer, dispatching on its mode."
  (let ((buf (slime-eat--ensure-target)))
    (with-current-buffer buf
      (cond
       ;; eat-eshell has a TUI running: route through eat-terminal.
       ((and (derived-mode-p 'eshell-mode)
             (slime-eat--eshell-under-eat-p)
             (bound-and-true-p eat-terminal))
        (slime-eat--send-to-eat text))
       ;; Plain eat buffer.
       ((bound-and-true-p eat-terminal)
        (slime-eat--send-to-eat text))
       ;; Eshell at prompt, or with a non-eat subprocess attached.
       ((derived-mode-p 'eshell-mode)
        (slime-eat--send-to-eshell text))
       (t (user-error "Target buffer %s is neither eat nor eshell"
                      (buffer-name)))))))

(evil-define-operator slime-eat-send-op (beg end type)
  "Evil operator: send the motion or text object to the eat target."
  :move-point nil
  (interactive "<R>")
  (let ((text (if (eq type 'line)
                  (buffer-substring-no-properties
                   (save-excursion (goto-char beg) (line-beginning-position))
                   (save-excursion (goto-char end) (line-end-position)))
                (buffer-substring-no-properties beg end))))
    (slime-eat-send-string (concat text "\n"))))

(defun slime-eat-send-line ()
  "Send the current line to the eat target."
  (interactive)
  (slime-eat-send-op (line-beginning-position)
                     (line-end-position)
                     'line))

(defvar slime-eat-mode-map (make-sparse-keymap)
  "Keymap used in `slime-eat-mode' buffers.
Left empty by the package; bind keys in your own config, e.g.:

  (evil-define-key \\='(normal visual) slime-eat-mode-map
    \"gz\" #\\='slime-eat-send-op)")

;;;###autoload
(define-minor-mode slime-eat-mode
  "Buffer-local mode exposing a keymap for slime-eat send commands."
  :lighter " Slime"
  :keymap slime-eat-mode-map)

(defvar slime-eat--hooked-modes nil
  "Modes currently hooked by `slime-eat-refresh-hooks'.")

;;;###autoload
(defun slime-eat-refresh-hooks ()
  "Install `slime-eat-mode' on every hook in `slime-eat-modes'."
  (interactive)
  (dolist (mode slime-eat--hooked-modes)
    (remove-hook (intern (format "%s-hook" mode)) #'slime-eat-mode))
  (setq slime-eat--hooked-modes nil)
  (dolist (mode slime-eat-modes)
    (add-hook (intern (format "%s-hook" mode)) #'slime-eat-mode)
    (push mode slime-eat--hooked-modes)))

(provide 'slime-eat)
;;; slime-eat.el ends here
