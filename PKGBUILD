# Maintainer: Martin/Geno <geno+dev {at} fireorbit {dot} de>
pkgname=gatemon-git
_pkgname=gatemon
_pkgauthor=FreifunkBremen
pkgver=r69.efa33b7
pkgrel=1
pkgdesc="Script to monitor the gateway servers of a Freifunk mesh network for outages"
arch=('any')
url="https://github.com/${_pkgauthor}/${_pkgname}"
license=('custom')
depends=('curl' 'monitoring-plugins' 'bind-tools')
backup=('etc/gatemon.cfg')
source=("${_pkgname}"::'git+https://github.com/FreifunkBremen/gatemon.git')
sha256sums=('SKIP')

pkgver() {
	cd "${srcdir}/${_pkgname}"
	printf "r%s.%s" "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
}

build() {
	cd "${srcdir}/${_pkgname}"
	make clean libpacketmark.so
}

package() {
	cd "${srcdir}/${_pkgname}"
	make DESTDIR="$pkgdir/" install
	mkdir "$pkgdir/usr"
	mv "$pkgdir/lib" "$pkgdir/usr/"
	install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
