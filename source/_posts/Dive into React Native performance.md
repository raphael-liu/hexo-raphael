---
title: Dive into React Native performance
date: 2016-10-25 17:47:14
tags: react-native
---
# [Dive into React Native performance](https://code.facebook.com/posts/895897210527114/)
[React Native](https://facebook.github.io/react-native/) allows you to build iOS and Android apps in JavaScript using [React](https://facebook.github.io/react/) and [Relay](https://facebook.github.io/relay/)'s declarative programming model. This leads to more concise, easier-to-understand code; fast iteration without a compile cycle; and easy sharing of code across multiple platforms. You can ship faster and focus on details that really matter, making your app look and feel fantastic. Optimizing performance is a big part of this. Here is the story of how we made React Native app startup twice as fast.

## Why the hurry?
With an app that runs faster, content loads quickly, which means people get more time to interact with it, and smooth animations make the app enjoyable to use. In emerging markets, where 2011 class phones on 2G networks are the majority, a focus on performance can make the difference between an app that is usable and one that isn't.
<!-- more -->
Since releasing React Native on iOS and on Android, we have been improving list view scrolling performance, memory efficiency, UI responsiveness, and app startup time. Startup sets the first impression of an app and stresses all parts of the framework, so it is the most rewarding and challenging problem to tackle.

## Always be measuring
We converted the Events Dashboard feature in the Facebook for iOS app to React Native (navigate to the More tab in the app and tap Events to see it). This was the perfect candidate for testing performance because the native product was already highly optimized and provided a typical “interactive list of items” experience.
![](https://scontent.xx.fbcdn.net/l/t39.2365-6/12679446_1168726623161282_931282499_n.jpg)
Fig. 1: The Events Dashboard screen

Next, we set up an automated CT-Scan performance test that helped us navigate to the rightmost tab, which then opens and closes the Events Dashboard 50 times. During each of these iterations, we are able to measure the time it takes from tapping the Events button to events being visible on the screen. We also added more detailed performance markers to give us a good idea of which steps in the startup process were slow and taking up CPU time.

Here is an overview of some of the steps we are measuring:

* Native Initialization: Initialize the JavaScript virtual machine and all the native modules (disk cache, network, UI manager, etc.).
* JS Init + Require: Read the minified JavaScript bundle file from disk and load it into the JavaScript virtual machine, which will parse it and generate bytecode as it requires the initial modules (mostly React, Relay, and their dependencies).
* Before Fetch: Load and execute the Events Dashboard application code, build the Relay query, and kick off reading from the on-disk cache.
* Fetch: Fetch data from the on-disk cache.
* JS Render: Instantiate all the React components and send them to the native UI manager module for display.
* Native Render: Calculate view sizes by computing the FlexBox layout on the shadow thread; create and position the views on the main thread.
![](https://fbcdn-dragon-a.akamaihd.net/hphotos-ak-xfp1/t39.2365-6/12679489_247741662231959_787037748_n.jpg)
Fig. 2: Events Dashboard startup performance

Our golden rule from then on: Never regress the test. We run it continuously to track performance improvements and regressions, and developers can run it on a specific commit to get a detailed performance analysis before pushing the change. Other tests have been set up to measure scroll performance and memory usage in the same way.

## What happens on startup
With automated performance tracking in place, we needed a tool that could give us more details on what exactly needed improvement during startup. We added detailed start/stop performance markers throughout our frameworks, collected the data, and used the catapult viewer to identify hot spots and blocking interactions across threads. You can trigger profiling on your app from the developer menu.

With React Native, your code is executed on the JavaScript thread. Whenever you want to write data to the disk, make a network request, or access any other native resource (like the camera), your code needs to call a native module. When you render your components with React, they will be forwarded to the UI manager native module, which will then perform layout and create the resulting views on the main thread. The bridge will forward your call to the module and call back to your code, if needed. In React Native, all native calls have to be asynchronous to avoid blocking the main thread or the JS thread.

In the below Events Dashboard startup visualization, we can see that the app, which is running on the JS queue, triggers a cache read for the events to be displayed, which is triggered on the async local storage queue. Once it gets the cached data back, the app renders the events cells on the JS queue with React, which then passes it on to the shadow queue for layout and finally to the main queue for view creation. This example shows multiple cache reads (using one common read operation may be faster) and a few React render operations on the JS thread that might be consolidated.
![](https://fbcdn-dragon-a.akamaihd.net/hphotos-ak-xpf1/t39.2365-6/12427047_188833171499254_295261012_n.jpg)
Fig. 3: Events Dashboard startup visualization

## Performance improvements
Here are a few of the most significant efficiency and scheduling improvements we have made to reach our results, with links to the relevant commits.

## Doing less
* Cleanup Require/Babel helpers (high impact): Removes helper code executed during require() that was specific to our website and not needed for React Native.

* Avoid copying and decoding strings when loading the bundle (medium impact): Passing a UTF-8 string to the JavaScriptCore virtual machine will cause it to trigger a slower conversion to UCS-2 format. Encoding it in ASCII format instead will avoid the conversion. Getting rid of the intermediate NSString representation also improves performance by avoiding one more conversion. We discovered these improvements through extensive benchmarking of the bundle loading step.

* Stripping DEV-only modules (low impact): Unlike compiled code, JavaScript doesn't have a preprocessor that can strip debugging features in release mode. Using a Babel transform, we were able to remove code living behind __DEV__ statements, effectively reducing bundle size, which improves JavaScript parse time.

* Generate event descriptions on the server (low impact): Instead of fetching data to generate a sentence describing which friends are coming to an event, generate it on the server, which reduces the data we have to receive and parse, and avoid all the client-side processing to generate the sentence.

## Scheduling
* Lazy requires (low impact): Instead of executing all JavaScript module require calls up front, trigger a require call only the first time we need it. This optimization effectively avoids requiring modules that are never used, and it has also proved to be successful on the web.

* Relay incremental cache read (high impact): Relay was initially written for the web and had only an in-memory response cache. The first on-disk response cache was reading the entire cache from the disk. By reading only the content required to fulfill a particular query, we significantly reduced the I/O overhead and native-to-JS bridge traffic.

* De-batching bridge calls, batch Relay calls (high impact): We initially thought that sending JS calls to native in batches would reduce the overhead of calling over the native-to-JS bridge, but performance analysis showed the overhead of JS calls to native was not a bottleneck: In fact, delaying UI or cache read calls to batch them with later calls also delayed work on the native thread, which harmed performance. In other cases, like the Relay cache read fetching data for multiple keys, batching proved to be a significant improvement.

* Early UI flushing (low impact): We also batched UI updates to enforce consistency, but sending layout commands as soon as they are ready proved to be more efficient because the native UI manager can work in parallel with the JavaScript thread.

* Lazy native modules loading (low impact): Initialize a native module only the first time we use it, which avoids initializing the modules we do not need.

* Lazy touch bindings on text components (low impact): Binding touch event callbacks takes a significant amount of time. Instead of doing all that work up front, we are now only binding the touch down event (when you first touch a target) and bind all the other callbacks only when you start touching the element.

* Defer popular events query (medium impact): The first screen of information is populated by the events query, and we will then show popular events after these. Deferring that query reduces contention when populating the screen with events.

## Prepare for light-speed
A few months ago, Events Dashboard startup took two seconds on the iPhone 5. After a lot of work from the React Native Performance, React Native, React, and Relay teams in London, Menlo Park, and New York, Events Dashboard startup is now twice as fast. Most of the improvements we made were done at the framework level, which means your React Native app will automatically benefit when migrating to the latest version of React Native.

These improvements are just the beginning: We continue to work on making every part of the stack faster, from JavaScript parse time to data-fetching performance. And you can contribute, learn how to make your apps faster, and ask any questions you may have in our community!