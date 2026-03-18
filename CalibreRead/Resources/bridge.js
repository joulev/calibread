// CalibreBridge — Swift ↔ foliate-js communication layer
//
// Injected into reader.html. Exposes a global CalibreBridge object that:
// - Opens an EPUB from calibre://book
// - Forwards foliate-js events to Swift via WKScriptMessageHandler
// - Exposes navigation/theme API callable from Swift's evaluateJavaScript

const post = (msg) => {
    try {
        window.webkit.messageHandlers.pageHandler.postMessage(msg)
    } catch (e) {
        console.error('Failed to post message:', e)
    }
}

// Compute section groups: each section index maps to the index of its nearest
// preceding section that has a TOC entry. Unnamed sections inherit from their
// named predecessor.
async function computeSectionGroups(book) {
    const sections = book.sections
    const toc = book.toc ?? []
    const ids = sections.map(s => s.id)

    // Collect all section indices that have TOC entries
    const namedSections = new Set()
    async function processTOC(items) {
        for (const item of items) {
            if (item.href && book.splitTOCHref) {
                try {
                    const [id] = await book.splitTOCHref(item.href)
                    const idx = ids.indexOf(id)
                    if (idx >= 0) namedSections.add(idx)
                } catch {}
            }
            if (item.subitems) await processTOC(item.subitems)
        }
    }
    await processTOC(toc)

    // Build groups: each section maps to its nearest preceding named section
    const groups = new Array(sections.length).fill(0)
    let currentGroup = 0
    for (let i = 0; i < sections.length; i++) {
        if (namedSections.has(i)) currentGroup = i
        groups[i] = currentGroup
    }
    return groups
}

// Pagination measurement using a real hidden foliate-paginator.
// This guarantees identical page counts to the visible paginator.
async function measureAllSections(book, styles, viewWidth, viewHeight, signal) {
    const sections = book.sections
    if (!sections?.length) return

    // Create a hidden container with the same dimensions as the visible view
    const container = document.createElement('div')
    container.style.cssText = `position:fixed;top:0;left:0;width:${viewWidth}px;height:${viewHeight}px;opacity:0;pointer-events:none;z-index:-1;`
    document.body.appendChild(container)

    // Create a real foliate-paginator with the same configuration
    await import('calibre://app/foliate/paginator.js')
    const paginator = document.createElement('foliate-paginator')
    paginator.style.cssText = 'width:100%;height:100%;'
    paginator.setAttribute('flow', 'paginated')
    paginator.setAttribute('gap', '5%')
    paginator.setAttribute('max-inline-size', '720px')
    paginator.setAttribute('max-column-count', '1')
    container.appendChild(paginator)
    paginator.open(book)
    if (styles) paginator.setStyles(styles)

    // Allow the paginator to initialize with a ResizeObserver tick
    await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))

    const total = sections.length
    const counts = []

    for (let i = 0; i < total; i++) {
        if (signal?.aborted) break

        try {
            if (sections[i].linear === 'no') {
                counts.push(1)
            } else {
                await paginator.goTo({ index: i })
                counts.push(Math.max(1, paginator.pages - 2))
            }
        } catch {
            counts.push(1)
        }

        if ((i + 1) % 4 === 0 || i === total - 1) {
            post({
                type: 'paginationProgress',
                completed: i + 1,
                total: total,
            })
        }
    }

    paginator.destroy?.()
    document.body.removeChild(container)

    if (!signal?.aborted) {
        post({
            type: 'paginationComplete',
            counts: counts,
        })
    }
}

let _paginationTimer = null
let _paginationAbort = null

function schedulePagination() {
    clearTimeout(_paginationTimer)
    // Abort any in-progress measurement
    if (_paginationAbort) _paginationAbort.abort()

    post({ type: 'paginationStarted' })

    _paginationTimer = setTimeout(() => {
        CalibreBridge.startPagination()
    }, 400)
}

const CalibreBridge = {
    view: null,
    _currentStyles: null,

    async open() {
        try {
            const view = document.createElement('foliate-view')
            document.body.appendChild(view)
            this.view = view

            // Fetch the EPUB file as a blob, then create a File object
            const res = await fetch('calibre://book')
            if (!res.ok) {
                post({ type: 'error', message: `Failed to fetch book: ${res.status} ${res.statusText}` })
                return false
            }
            const blob = await res.blob()
            const file = new File([blob], 'book.epub', { type: 'application/epub+zip' })

            await view.open(file)

            view.addEventListener('relocate', (e) => {
                const { fraction, location, tocItem, pageItem, cfi } = e.detail

                // Get page info from the renderer (paginator)
                // paginator uses 1 padding page on each side, so text pages = pages - 2
                const renderer = view.renderer
                let sectionPage = null
                let sectionPages = null
                if (renderer && typeof renderer.page === 'number' && typeof renderer.pages === 'number') {
                    sectionPage = Math.max(1, renderer.page)
                    sectionPages = Math.max(1, renderer.pages - 2)
                }

                // Get section index from renderer contents
                let sectionIndex = null
                try {
                    const contents = renderer.getContents?.()
                    if (contents?.length > 0) sectionIndex = contents[0].index
                } catch {}

                post({
                    type: 'relocate',
                    fraction: fraction ?? 0,
                    cfi: cfi ?? null,
                    tocLabel: tocItem?.label ?? null,
                    tocHref: tocItem?.href ?? null,
                    sectionPage: sectionPage,
                    sectionPages: sectionPages,
                    sectionIndex: sectionIndex,
                    totalSections: view.book?.sections?.length ?? null,
                })
            })

            view.addEventListener('load', (e) => {
                const { doc, index } = e.detail
                const style = doc.defaultView?.getComputedStyle(doc.documentElement)
                const wm = style?.writingMode || ''
                const isVertical = wm === 'vertical-rl' || wm === 'vertical-lr'
                post({
                    type: 'load',
                    index: index,
                    isVertical: isVertical,
                })

                // Forward keyboard events from within iframes to Swift
                doc.addEventListener('keydown', (ke) => {
                    post({
                        type: 'keydown',
                        key: ke.key,
                    })
                })
            })

            // Send TOC and metadata to Swift
            const book = view.book
            const toc = flattenTOC(book.toc ?? [])
            const sectionFractions = view.getSectionFractions()
            const sectionGroups = await computeSectionGroups(book)
            post({
                type: 'bookReady',
                title: formatLangMap(book.metadata?.title) || '',
                author: formatContributor(book.metadata?.author) || '',
                toc: toc,
                sectionFractions: sectionFractions,
                sectionGroups: sectionGroups,
                dir: book.dir ?? 'ltr',
            })

            // Set default layout
            view.renderer.setAttribute('flow', 'paginated')

            // Re-paginate on window resize
            window.addEventListener('resize', () => schedulePagination())

            return true
        } catch (e) {
            post({ type: 'error', message: `open() failed: ${e.message}\n${e.stack}` })
            return false
        }
    },

    async init(lastLocation) {
        try {
            if (!this.view) return
            await this.view.init({ lastLocation: lastLocation || undefined })
        } catch (e) {
            post({ type: 'error', message: `init() failed: ${e.message}` })
        }
    },

    /// Start background pagination measurement for all sections.
    startPagination() {
        if (!this.view?.book) return
        if (_paginationAbort) _paginationAbort.abort()
        _paginationAbort = new AbortController()
        const rect = this.view.getBoundingClientRect()
        measureAllSections(this.view.book, this._currentStyles, rect.width, rect.height, _paginationAbort.signal)
    },

    next() {
        this.view?.next()
    },

    prev() {
        this.view?.prev()
    },

    goLeft() {
        this.view?.goLeft()
    },

    goRight() {
        this.view?.goRight()
    },

    goTo(target) {
        this.view?.goTo(target)
    },

    goToFraction(frac) {
        this.view?.goToFraction(frac)
    },

    setStyles(css) {
        this._currentStyles = css
        this.view?.renderer?.setStyles?.(css)
        schedulePagination()
    },

    setLayout(gap, maxInlineSize, maxColumnCount) {
        const r = this.view?.renderer
        if (!r) return
        if (gap != null) r.setAttribute('gap', String(gap))
        if (maxInlineSize != null) r.setAttribute('max-inline-size', typeof maxInlineSize === 'number' ? maxInlineSize + 'px' : String(maxInlineSize))
        if (maxColumnCount != null) r.setAttribute('max-column-count', String(maxColumnCount))
    },
}

function flattenTOC(items, depth = 0) {
    const result = []
    for (const item of items) {
        result.push({
            label: item.label ?? '',
            href: item.href ?? '',
            depth: depth,
        })
        if (item.subitems?.length) {
            result.push(...flattenTOC(item.subitems, depth + 1))
        }
    }
    return result
}

function formatLangMap(x) {
    if (!x) return ''
    if (typeof x === 'string') return x
    const keys = Object.keys(x)
    return x[keys[0]] ?? ''
}

function formatContributor(x) {
    if (!x) return ''
    if (typeof x === 'string') return x
    if (Array.isArray(x)) return x.map(formatContributor).filter(Boolean).join(', ')
    if (typeof x === 'object' && x.name) return formatLangMap(x.name)
    return ''
}

window.CalibreBridge = CalibreBridge
