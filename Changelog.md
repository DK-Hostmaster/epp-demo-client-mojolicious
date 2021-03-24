# Changelog for EPP Demo Client

## 1.6.0 2021-03-24 Feature release, Update not required

- Added entries for DKHM XSD version 4.3 in XSD drop-down

## 1.5.1 2021-03-16 Bug fix release, Update recommended

- Implementation of `dkhm:autoRenew` introduced in release 1.4.0 is too intrusive and was set with every command

- Added missing entry for secDNS namespace version 1.0 in XSD drop-down

- Added missing entry for DKHM namespace version 1.0 in XSD drop-down

- Added entries for DKHM XSD versions 4.1 and 4.2 in XSD drop-down

## 1.5.0 2021-01-25 Feature release, Update recommended

- Added support for the DKHM extension `dkhm:withdraw`, PR #42

## 1.4.0 2020-02-06 Feature release, Update recommended

- Added support for the DKHM extension `dkhm:autoRenew` for create domain, PR #41

## 1.3.2 2020-02-26 Bug fix release, Update recommended

- Addressed issue #35 a method had disappeared

- Addressed issue #34 reordering XML elements

## 1.3.1 2020-02-06 Bug fix release, Update recommended

- Bug fix release, addressing issues introduced in 1.2.X

## 1.3.0 2020-02-06 Feature release, Update recommended

- Implementation of optional DKHM extension for delete domain command for setting a deletion date, PR #30

## 1.2.1 2020-02-06 Bug fix release, Update recommended

- Implementation of handling of AuthInfo was too elaborate and broke create contact and mandatory requirement for AuthInfo, PR #29

## 1.2.0 2020-01-27 Feature release, Update recommended

- Added support for AuthInfo, please see our RFC: https://github.com/DK-Hostmaster/DKHM-RFC-AuthInfo

- Added support for XSD handling

- Fixed some minor issues (most introduced with the above feature changes)

## 1.1.0 2019-01-22 Feature release, Update recommended

- Added support for DNSSEC extension, issue #25

## 1.0.2 2018-02-02

- Added propagation of the risk assessment to the poll message for create domain name

## 1.0.1 2016-10-22

- Addressed issue #11, validation information now displayed for contact info command

- Addressed issue #13, check command now displays all available data

## 1.0.0 2016-10-01

- Initial release
