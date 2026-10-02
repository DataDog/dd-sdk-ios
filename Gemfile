source 'https://rubygems.org'

# dd-sdk-ios no longer ships podspecs, but IntegrationTests/Podfile still uses `pod '...', :path
# => '..'` to build the SDK's own UI test suite against local source -- its `post_install`
# injects DD_SDK_COMPILED_FOR_TESTING, which SPM has no equivalent mechanism for. See RUM-18782.
gem 'cocoapods', '1.15.2'
