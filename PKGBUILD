# Maintainer: Martin/Geno <geno+dev {at} fireorbit {dot} de>

pkgname=gatemon-git
_pkgname=gatemon
_pkgauthor=FreifunkBremen
pkgver=r37.615d977
pkgrel=1
pkgdesc=""
arch=('any')
url="https://github.com/${_pkgauthor}/${_pkgname}"
license=('GPL3')
depends=('monitoring-plugins' 'bind-tools')
backup=('etc/check-all-vpn-exits.cfg')
source=('check-all-vpn-exits.cfg' 'check-all-vpn-exits.sh'
	'check-all-vpn-exits.service' 'check-all-vpn-exits.timer'
	'Makefile' 'check_dhcp.c')
sha256sums=('SKIP' 'SKIP'
	'SKIP' 'SKIP'
	'SKIP' 'SKIP')

pkgver() {
	# echo "$(git rev-list --count HEAD).$(git rev-parse --short HEAD)"
	printf "r%s.%s" "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
}

build() {
	make clean check_dhcp
}

package() {
	install -Dm755 "check-all-vpn-exits.sh" "${pkgdir}/usr/local/bin/check-all-vpn-exists"
	install -Dm755 "check_dhcp" "${pkgdir}/usr/local/bin/check_dhcp"
	install -Dm600 "check-all-vpn-exits.cfg" "${pkgdir}/etc/check-all-vpn-exits.cfg"
	install -Dm644 "check-all-vpn-exits.service" "${pkgdir}/usr/lib/systemd/system//check-all-vpn-exits.service"
	install -Dm644 "check-all-vpn-exits.timer" "${pkgdir}/usr/lib/systemd/system//check-all-vpn-exits.timer"
}

