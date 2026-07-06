//
//  ComicReader-Bridging-Header.h
//  Comic Reader
//
//  Exposes the vendored UnrarKit (Objective-C, in Vendor/UnrarKit) to Swift so
//  RarComicArchive can read CBR files. The <UnrarKit/…> imports resolve via the
//  HEADER_SEARCH_PATHS entry ($(SRCROOT)/Vendor). URKArchive.h only pulls in the
//  C-safe unrar DLL headers (raros.hpp / dll.hpp), so it is fine in a plain
//  Objective-C bridging context.
//

#import <UnrarKit/URKArchive.h>
#import <UnrarKit/URKFileInfo.h>
