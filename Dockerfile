FROM archlinux
RUN pacman -Syu --noconfirm && pacman -S --noconfirm git neovim python
