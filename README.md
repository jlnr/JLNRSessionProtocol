# JLNRSessionProtocol

This is a sketch of a library **that is not ready for production use** (see below).

## What does it do?

A common pattern in iOS is that when the user logs in, the app receives a time-limited access token to perform further API requests.
After a given amount of time (several hours or days), the token expires, and all subsequent API requests will return the status 401.
It is then time for the application to send another login request, store the new token, and retry.

`JLNRSessionProtocol` is a subclass of `NSURLProtocol` that tries to hide session management logic from the rest of the app by intelligently performing login requests as needed, so that other parts of the application can be written as if the user was always automatically logged in.

This has the following advantages:

* Session management can be pulled out of API service classes.
* It can be tricky to configure third-party libraries (like the fantastic SDWebImage) to understand session expiry.
* A naive approach to session renewal will send a login request as soon as any HTTP request unexpectedly returns 401.
  If several requests are performed in parallel, this will lead to multiple login requests being started in response.
  By handling session renewal in one central place, the application can be smarter about this, and only send *one* login request when the session times out.
  (The current implementation of `JLNRSessionProtocol` does not yet do this.)

## How do I use it?

By creating a custom session class that conforms to `JLNRSession` and implements your app-specific session management logic.

[The test suite](Tests/JLNRSessionProtocolTests/JLNRSessionProtocolTests.swift) is the best way to understand the design of this library.

## What is the state of this project?

This is only a proof of concept.
I stopped working on this library when the backend I was developing against was rewritten to use non-expiring access tokens.

I have published the current code along with fresh tests for future reference by me or others.

These are show-stoppers and should be looked at before using this in production:

* The current implementation still uses `NSURLConnection`(!), and it should be ported to use `NSURLSession` instead.
* There are not enough tests yet for such a critical part of an app.
* The current implementation can cause multiple login requests to be sent in parallel unless `HTTPMaximumConnectionsPerHost` is set to 1.
* This library was more useful in the world of `NSURLConnection`, where all `NSURLProtocol`s could transparently affect each request in the app.
  Post iOS 7.0, custom protocols only work with `[NSURLSession sharedSession]`, or in custom `NSURLSession`s where they have been added to the `protocolClasses` configuration property.
  This is a limitation in how `NSURLProtocol` interacts with `NSURLSession`, and not something this library can work around.

## Installation

You can simply copy the two files in `Classes` into your project, but the easiest way is to use [CocoaPods](http://cocoapods.org).

[CocoaPods](http://cocoapods.org) is a dependency manager for Objective-C, which automates and simplifies the process of using 3rd-party libraries like JLNRSessionProtocol in your projects.

#### Podfile

```ruby
platform :ios, "7.0" # for NSURLSession

pod "JLNRSessionProtocol", git: "https://github.com/jlnr/JLNRSessionProtocol"
```

## License

`JLNRSessionProtocol` is released under the [MIT License](http://www.opensource.org/licenses/MIT).
