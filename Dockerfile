FROM archlinux:base-devel
WORKDIR /setup
RUN pacman -Sy git neovim python --noconfirm
RUN useradd -m test

USER test
RUN git clone --depth 1 https://github.com/nvim-lua/plenary.nvim ~/.local/share/nvim/site/pack/vendor/start/plenary.nvim
RUN mkdir -p /home/test/.cache/nvim/packer.nvim
RUN touch /home/test/.cache/nvim/packer.nvim/test_completion{,1,2,3}

USER test
RUN mkdir -p /home/test/.local/share/nvim/site/pack/packer/start/packer.nvim/
WORKDIR /home/test/.local/share/nvim/site/pack/packer/start/packer.nvim/
COPY . ./

USER root
RUN chmod 777 -R /home/test/.local/share/nvim/site/pack/packer/start/packer.nvim
RUN touch /home/test/.cache/nvim/packer.nvim/not_writeable

USER test
ENTRYPOINT make test
