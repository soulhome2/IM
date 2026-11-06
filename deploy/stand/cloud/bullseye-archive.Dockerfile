# Локальная подмена debian:bullseye: Debian 11 ушёл в archive.debian.org, на deb.debian.org пакеты security дают 404.
FROM debian:bullseye@sha256:6f519a81440354a85eb592c5f32109ab80605f6b892455983a6f618bf87fabe9
RUN printf 'deb http://archive.debian.org/debian bullseye main\ndeb http://archive.debian.org/debian-security bullseye-security main\ndeb http://archive.debian.org/debian bullseye-updates main\n' > /etc/apt/sources.list \
 && rm -f /etc/apt/sources.list.d/* \
 && echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99archive
LABEL local.override="bullseye -> archive.debian.org"
