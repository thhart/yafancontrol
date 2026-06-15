Name:           yafancontrol
Version:        1.3
Release:        1%{?dist}
Summary:        Yet Another Fan Control - in-process ThinkPad fan controller

License:        Apache-2.0
URL:            https://github.com/thhart/yafancontrol
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  gcc
BuildRequires:  systemd-rpm-macros
%{?systemd_requires}

%description
Controls the fan speed on ThinkPad laptops based on temperature thresholds,
lifting the firmware's conservative fan cap so the machine does not throttle
under sustained load. C implementation: reads temperature and fan RPM with
direct file I/O and drives /proc/acpi/ibm/fan in a closed loop, forking no
processes. Requires the thinkpad_acpi module loaded with fan_control=1.

%prep
%autosetup

%build
cc -O2 -Wall -Wextra -o yafancontrol yafancontrol.c

%install
install -Dm0755 yafancontrol            %{buildroot}%{_bindir}/yafancontrol
install -Dm0644 yafancontrol.cfg        %{buildroot}%{_sysconfdir}/yafancontrol/yafancontrol.cfg
install -Dm0644 yafancontrol.service    %{buildroot}%{_unitdir}/yafancontrol.service

%files
%license LICENSE
%doc README.md
%{_bindir}/yafancontrol
%config(noreplace) %{_sysconfdir}/yafancontrol/yafancontrol.cfg
%{_unitdir}/yafancontrol.service

%post
%systemd_post yafancontrol.service

%preun
%systemd_preun yafancontrol.service

%postun
%systemd_postun_with_restart yafancontrol.service

%changelog
* Mon Jun 15 2026 Thomas Hartwig <thomas.hartwig@gmail.com> - 1.3-1
- Idle path polls temperature only; fan RPM reads + level writes (and the EC
  watchdog) happen only while actively cooling, ending a ~30 Hz EC GPE storm.
* Mon Jun 15 2026 Thomas Hartwig <thomas.hartwig@gmail.com> - 1.2-1
- C reimplementation of the bash yafancontrol (no per-second process churn);
  fan_speed_min/max config keys + --calibrate; EC fan watchdog fail-safe.
