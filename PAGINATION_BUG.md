# Pagination Bug Analysis

## Symptom

The ereader shows "Paginating... 0/55" permanently. The pagination process never starts measuring any chapters.

## Root Cause

**`contentSize` is never set to a non-zero value**, so `startPagination()` always fails the guard:

```swift
guard let service = epubService,
      contentSize.width > 0, contentSize.height > 0 else { return }
```

### Why `contentSize` stays at zero

The current code uses a `PreferenceKey`-based `GeometryReader` in `.background` on the `EPUBWebView` (an `NSViewRepresentable`):

```swift
EPUBWebView(...)
    .background {
        GeometryReader { geo in
            Color.clear
                .preference(key: ContentSizeKey.self, value: geo.size)
        }
    }
    .onPreferenceChange(ContentSizeKey.self) { size in
        if size.width > 0, size.height > 0 {
            contentSize = size
        }
    }
```

**The `onPreferenceChange` callback never fires with a valid size.** Preference propagation from a `.background` GeometryReader on an `NSViewRepresentable` view is unreliable on macOS 26. The preference is set but never reaches the `onPreferenceChange` handler.

### Fix

Replace the preference-based approach with a direct `GeometryReader` wrapper:

```swift
GeometryReader { geo in
    EPUBWebView(...)
        .onAppear {
            if geo.size.width > 0, geo.size.height > 0 {
                contentSize = geo.size
            }
        }
        .onChange(of: geo.size) { _, newSize in
            if newSize.width > 0, newSize.height > 0 {
                contentSize = newSize
            }
        }
}
```

This reads the geometry directly without relying on preference propagation. The `GeometryReader` fills the available space in the `HStack` (between the navigation arrows), giving the `EPUBWebView` the correct size and reporting it reliably.

The `ContentSizeKey` `PreferenceKey` struct can be removed.

## Secondary Issue: Race Condition in EPUBPaginator

There is a potential race condition in `EPUBPaginator.measureNext()` that may surface once the primary fix is applied:

```swift
webView.loadFileURL(chapter.fileURL, allowingReadAccessTo: contentBaseURL)

await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
    self.navigationContinuation = cont
}
```

`loadFileURL` starts navigation, and `didFinish` could fire **before** `navigationContinuation` is set. Since `EPUBPaginator` is `@MainActor` and the delegate callbacks also fire on the main actor, this race can only happen if `didFinish` is delivered synchronously within `loadFileURL` (unlikely but possible). If it does happen, `didFinish` finds `navigationContinuation == nil`, does nothing, and the continuation hangs forever.

### Fix

Use a flag to detect if the delegate fired before the continuation was entered:

```swift
private var navigationDidComplete = false

func measureNext() async -> (index: Int, pageCount: Int)? {
    // ...
    navigationDidComplete = false
    navigationContinuation = nil

    webView.loadFileURL(chapter.fileURL, allowingReadAccessTo: contentBaseURL)

    if navigationDidComplete {
        navigationDidComplete = false
    } else {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.navigationContinuation = cont
        }
    }
    // ...
}
```

And in each delegate method:

```swift
func webView(_ wv: WKWebView, didFinish navigation: WKNavigation!) {
    if let cont = navigationContinuation {
        navigationContinuation = nil
        cont.resume()
    } else {
        navigationDidComplete = true
    }
}
```

**Important:** Do NOT move `webView.loadFileURL()` inside the `withCheckedContinuation` closure. That closure is `@Sendable` and may not execute on the main actor, which will break WKWebView (causes blank pages on all pages after the first in each chapter).

## Files to Modify

- `CalibreRead/Views/Reader/EPUBReaderView.swift` — GeometryReader fix
- `CalibreRead/Services/EPUBPaginator.swift` — race condition fix (optional, may not be needed in practice)
