#!/bin/zsh

objcRetVal=1
while [[ $objcRetVal -ne 0 ]] ; do
    sleep 5m ;
	pod repo update ;
	pod spec lint --allow-warnings DatadogSDKObjc.podspec ;
    objcRetVal=$? ;
done

alamofireRetVal=1
while [[ $alamofireRetVal -ne 0 ]] ; do
	sleep 30s ;
	pod repo update ;
    pod spec lint --allow-warnings DatadogSDKAlamofireExtension.podspec ;
   	alamofireRetVal=$? ;
done

crashReportingRetVal=1
while [[ $crashReportingRetVal -ne 0 ]] ; do
   sleep 30s ;
   pod repo update ;
   pod spec lint --allow-warnings DatadogSDKCrashReporting.podspec ;
   crashReportingRetVal=$? ;
done

pod trunk me
pod trunk push --allow-warnings DatadogSDKObjc.podspec
pod trunk push --allow-warnings DatadogSDKAlamofireExtension.podspec
pod trunk push --allow-warnings DatadogSDKCrashReporting.podspec
