// CalibreReader — EPUB pagination engine
//
// Injected into each EPUB chapter's WKWebView after navigation completes.
// Handles CSS column-based pagination, page navigation via translateX,
// and reports page state back to Swift via WKScriptMessageHandler.
//
// Supports both horizontal-tb (normal LTR text) and vertical-rl
// (Japanese/Chinese vertical text) writing modes. In vertical-rl,
// columns flow right-to-left, so the transform direction and keyboard
// mappings are reversed.
//
// Expects:
//   - A <style id="calibreread-style"> element (injected before this script)
//   - window.webkit.messageHandlers.pageHandler (WKScriptMessageHandler)
//
// Messages sent to Swift:
//   { current: Int, total: Int }         — page position update
//   { action: "nextChapter" }            — user navigated past last page
//   { action: "prevChapter" }            — user navigated before first page
//   { action: "contentReady" }           — content is visible and ready
//   { action: "contentHidden" }          — content hidden during transition
//   { action: "writingMode", isVertical: Bool } — detected writing mode

(function() {
    var MAX_CONTENT_WIDTH = 640;
    var PADDING_MIN_H = 60;
    var PADDING_V = 40;
    var RESIZE_DEBOUNCE_MS = 150;

    var CalibreReader = {
        currentPage: 0,
        totalPages: 1,
        pageWidth: 0,
        isVertical: false,

        detectWritingMode: function() {
            var htmlStyle = getComputedStyle(document.documentElement);
            var bodyStyle = getComputedStyle(document.body);
            var htmlWM = htmlStyle.writingMode || htmlStyle['-webkit-writing-mode'] || '';
            var bodyWM = bodyStyle.writingMode || bodyStyle['-webkit-writing-mode'] || '';
            this.isVertical = (htmlWM === 'vertical-rl' || bodyWM === 'vertical-rl');
            window.webkit.messageHandlers.pageHandler.postMessage({
                action: 'writingMode',
                isVertical: this.isVertical
            });
        },

        recalculate: function() {
            this.detectWritingMode();

            var vw = window.innerWidth;
            var vh = window.innerHeight;
            var paddingH = Math.max(PADDING_MIN_H, (vw - MAX_CONTENT_WIDTH) / 2);
            var gap = paddingH * 2;
            var colWidth = vw - gap;

            document.body.style.columnWidth = colWidth + 'px';
            document.body.style.columnGap = gap + 'px';
            document.body.style.height = vh + 'px';
            document.body.style.padding = PADDING_V + 'px ' + paddingH + 'px';

            this.pageWidth = vw;

            // Force layout reflow before measuring
            document.body.offsetHeight;

            var scrollW = document.body.scrollWidth;
            this.totalPages = Math.max(1, Math.round(scrollW / this.pageWidth));

            if (this.currentPage >= this.totalPages) {
                this.currentPage = this.totalPages - 1;
            }

            this.applyTransform();
            this.reportPage();
        },

        applyTransform: function() {
            if (this.isVertical) {
                // vertical-rl: columns flow right-to-left. Without transform,
                // the viewport shows the rightmost content (page 0 / first page).
                // To show page N, shift the body to the RIGHT by N * pageWidth
                // so columns further to the left come into view.
                document.body.style.transform = 'translateX(' + (this.currentPage * this.pageWidth) + 'px)';
            } else {
                // horizontal-tb: columns flow left-to-right. Page 0 is at
                // the left edge; shift left to reveal later pages.
                document.body.style.transform = 'translateX(-' + (this.currentPage * this.pageWidth) + 'px)';
            }
        },

        reportPage: function() {
            window.webkit.messageHandlers.pageHandler.postMessage({
                current: this.currentPage + 1,
                total: this.totalPages
            });
        },

        goToPage: function(n) {
            this.currentPage = Math.max(0, Math.min(n, this.totalPages - 1));
            this.applyTransform();
            this.reportPage();
        },

        nextPage: function() {
            if (document.body.style.opacity === '0') return;
            if (this.currentPage < this.totalPages - 1) {
                this.goToPage(this.currentPage + 1);
            } else {
                window.webkit.messageHandlers.pageHandler.postMessage({ action: 'nextChapter' });
            }
        },

        prevPage: function() {
            if (document.body.style.opacity === '0') return;
            if (this.currentPage > 0) {
                this.goToPage(this.currentPage - 1);
            } else {
                window.webkit.messageHandlers.pageHandler.postMessage({ action: 'prevChapter' });
            }
        },

        goToFraction: function(f) {
            var page = Math.round(f * Math.max(0, this.totalPages - 1));
            this.goToPage(page);
        },

        getFraction: function() {
            if (this.totalPages <= 1) return 0;
            return this.currentPage / (this.totalPages - 1);
        }
    };

    window.CalibreReader = CalibreReader;

    // Wait for all images and fonts to finish loading.
    // Returns a Promise that resolves when everything is ready.
    function waitForAssets() {
        var images = Array.from(document.querySelectorAll('img'));
        var imagePromises = images.map(function(img) {
            if (img.complete) return Promise.resolve();
            return new Promise(function(resolve) {
                img.addEventListener('load', resolve, { once: true });
                img.addEventListener('error', resolve, { once: true });
            });
        });
        var fontReady = document.fonts ? document.fonts.ready : Promise.resolve();
        return Promise.all([fontReady].concat(imagePromises));
    }

    // Initial calculation: recalculate immediately with rAF for text-only
    // layout, then recalculate again once all assets finish loading.
    requestAnimationFrame(function() {
        CalibreReader.recalculate();
        if (!window._CalibreWaitForFraction) {
            document.body.style.opacity = '1';
            window.webkit.messageHandlers.pageHandler.postMessage({ action: 'contentReady' });
        }
    });

    waitForAssets().then(function() {
        CalibreReader.recalculate();
    });

    // Watch for dynamically inserted images (e.g. lazy-loaded) and
    // recalculate when they finish loading.
    var observer = new MutationObserver(function(mutations) {
        mutations.forEach(function(m) {
            m.addedNodes.forEach(function(node) {
                if (node.tagName === 'IMG' && !node.complete) {
                    node.addEventListener('load', function() {
                        CalibreReader.recalculate();
                    }, { once: true });
                }
            });
        });
    });
    observer.observe(document.body, { childList: true, subtree: true });

    // Recalculate on resize — debounced since resize fires rapidly
    var resizeTimer = null;
    window.addEventListener('resize', function() {
        document.body.style.opacity = '0';
        window.webkit.messageHandlers.pageHandler.postMessage({ action: 'contentHidden' });
        clearTimeout(resizeTimer);
        resizeTimer = setTimeout(function() {
            CalibreReader.recalculate();
            document.body.style.opacity = '1';
            window.webkit.messageHandlers.pageHandler.postMessage({ action: 'contentReady' });
        }, RESIZE_DEBOUNCE_MS);
    });

    // Handle keyboard navigation within the webview.
    // For vertical-rl, left/right arrows are swapped: left = next, right = prev.
    document.addEventListener('keydown', function(e) {
        if (document.body.style.opacity === '0') return;
        var isVertical = CalibreReader.isVertical;
        if (e.key === 'ArrowRight') {
            e.preventDefault();
            if (isVertical) { CalibreReader.prevPage(); } else { CalibreReader.nextPage(); }
        } else if (e.key === 'ArrowLeft') {
            e.preventDefault();
            if (isVertical) { CalibreReader.nextPage(); } else { CalibreReader.prevPage(); }
        } else if (e.key === ' ') {
            e.preventDefault();
            CalibreReader.nextPage();
        }
    });

    // Prevent native scrolling (both wheel and trackpad)
    document.addEventListener('wheel', function(e) { e.preventDefault(); }, { passive: false });
    document.addEventListener('scroll', function(e) {
        window.scrollTo(0, 0);
        document.documentElement.scrollLeft = 0;
    });
})();
