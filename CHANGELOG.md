Change Log
==========

<!--
subsections:
### Added
### Changed
### Removed
### Fixed
-->

0.2.0
-----
Released on 2020-02-13.

### Added
- Added changelog.
  [#10](https://github.com/y10k/riser/issues/10)

### Changed
- Changed to semantic versioning.
  [#7](https://github.com/y10k/riser/issues/7)

### Fixed
- Suppressed warnings on Ruby 2.7.
  [#8](https://github.com/y10k/riser/issues/8)
- Arguments forwarding compatible with Ruby 2.6 and 2.7.
  [#9](https://github.com/y10k/riser/issues/9)

0.1.15
------
Released on 2019-12-11.

### Fixed
- In Ruby 2.6, to avoid converting keyword arguments to Hash on
  stream's gets method.
  [89dc97cd](https://github.com/y10k/riser/commit/89dc97cd7baa48d992c6d15d8a05d4a10bc9b351)

0.1.14
------
Released on 2019-12-10.

### Added
- Stream's gets method may take optional arguments.
  [#6](https://github.com/y10k/riser/issues/6)

0.1.13
------
Released on 2019-11-19.

### Fixed
- Make tags not missing on read operations of wrapped stream.
  [30918d4c](https://github.com/y10k/riser/commit/30918d4c8a72bdb04aba4fc7b68ecc7e88ea4eee)

0.1.12
------
Released on 2019-11-15.

### Added
- Logging I/O operations with readable tag.
  [#4](https://github.com/y10k/riser/issues/4)
- Umask(2) for security.
  [#5](https://github.com/y10k/riser/issues/5)

0.1.11
------
Released on 2019-08-08.

### Added
- Add optional DRb server configuration to DRb services.
  [#3](https://github.com/y10k/riser/issues/3)

0.1.10
------
Released on 2019-07-04.

0.1.9
-----
Released on 2019-06-09.

0.1.8
-----
Released on 2019-04-14.

0.1.7
-----
Released on 2019-04-01.

0.1.6
-----
Released on 2019-03-17.

0.1.5
-----
Released on 2019-03-01.

0.1.4
-----
Released on 2019-02-22.

0.1.3
-----
Released on 2019-02-16.

0.1.2
-----
Released on 2019-02-09.

0.1.1
-----
Released on 2019-02-06.

0.1.0
-----
Released on 2019-02-06.
