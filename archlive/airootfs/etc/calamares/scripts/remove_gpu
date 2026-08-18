#!/usr/bin/env bash

case "$(lspci | grep -w "VGA" | head -n 1 | awk '{print $5}')" in
	NVIDIA)	pkgname=vulkan-radeon ;;
	AMD | *)	pkgname=nvidia-open ;;
esac

[[ $(pacman -Q "${pkgname}" 2>/dev/null) ]] && pacman -Rs --noconfirm "${pkgname}"

exit 0
