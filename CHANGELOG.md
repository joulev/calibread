# Changelog

## [1.1.1](https://github.com/joulev/calibread/compare/v1.1.0...v1.1.1) (2026-03-21)


### Bug Fixes

* **ci:** remove redundant release-type from workflow ([17f8565](https://github.com/joulev/calibread/commit/17f856569da441fe182b295e0181594a2eeecf11))
* make furigana (ruby text) non-selectable in EPUB reader ([b3461f5](https://github.com/joulev/calibread/commit/b3461f5443660e535b9f1fa9d4841532d5712d99))
* reduce idle memory usage by fixing WKWebView retain cycles and leaks ([10d90d2](https://github.com/joulev/calibread/commit/10d90d221f558da24e218475340dc51788c400fa))
* save reading progress on every page turn instead of only on view disappear ([62a52f1](https://github.com/joulev/calibread/commit/62a52f1c09f019f2d5a79ff3e8a37647a0ba33ab))

## [1.1.0](https://github.com/joulev/calibread/compare/v1.0.1...v1.1.0) (2026-03-19)


### Features

* add font family selector with main and supplemental fonts ([8862ecd](https://github.com/joulev/calibread/commit/8862ecd8ac1fdb459c3a4a190263b76cfead57cf))
* add recently read books to dock menu and File menu ([9f1c2b6](https://github.com/joulev/calibread/commit/9f1c2b62f25a6d4300c2749799d2ed1a82d3fd55))


### Bug Fixes

* prevent WebKit from extracting EPUBs to ~/Documents ([b31fbf8](https://github.com/joulev/calibread/commit/b31fbf8fbb2d3cd2f09d57019b201fb637edd744))
