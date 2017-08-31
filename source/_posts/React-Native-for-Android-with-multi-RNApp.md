---
title: Android多个React-Native模块的实现及源码解读
date: 2016-11-16 15:31:14
tags: react-native
reward: true
---
这里我们废话不多说,只围绕主题讲一些技术方面的干货.(本文基于React-Native0.36.0版本)

我们之所以在native app中引入react-native(以下简称RN)框架,是为了将native app中的一些不确定的UI布局,逻辑,业务,流程等等因素,交由远端来控制.也就是说,RN的bundle文件都是由远端下发,然而我们为了最优化展现RN页面,往往都会提前下载好所需要的bundle文件以节省网络交互时间.所以这篇博客我们是基于RN各模块(ComponentName)所对应的JS bundle文件已经下载到本地目标文件夹的前提下来写的.关于bundle文件的版本管理等我们在文末会详细介绍.
<!-- more -->
# ReactNativeHost
我们将RN库引入工程之后,第一件事情就是改造Application类.我们需要在自己的Application中实现一个接口----ReactApplication

```
public interface ReactApplication {
    ReactNativeHost getReactNativeHost();
}
```
这个接口中只有一个方法,而ReactNativeHost是一个抽象类,其中有两个抽象方法需要实现(一会将提到).这个方法返回ReactNativeHost对象,这个对象里面可以指定RN的调试模式,以及native给JS暴露的一些通信模块,同时还可以指定当前上下文加载的bundle文件路径.为了达到多个RN模块的切换,我们在Application中维护了一个<bundlePath,ReactNativeHost>的map(为什么这么做?紧接着会介绍):

`private HashMap<String, ReactNativeHost> mReactHostMap = MapBuilder.newHashMap();`

来看看我们是怎么实现上面的接口以及如何维护这个map的:

```
public String gReactNativeBundlePath = "myBundlePath...";

@Override
    public ReactNativeHost getReactNativeHost() {
        synchronized (gReactNativeBundlePath) {
            if (!mReactHostMap.containsKey(gReactNativeBundlePath)) {
                ReactNativeHost host = new ReactNativeHost(this) {
                    @Override
                    protected boolean getUseDeveloperSupport() {
                        return BuildConfig.REACT_DEBUG;
                    }

                    @Override
                    protected List<ReactPackage> getPackages() {
                        return Arrays.asList(new MainReactPackage(), new CustomReactPackage());
                    }

                    @Override
                    protected String getJSBundleFile() {
                        return gReactNativeBundlePath;
                    }
                };
                mReactHostMap.put(gReactNativeBundlePath, host);
            }
            return mReactHostMap.get(gReactNativeBundlePath);
        }
    }
```
先来看看我们创建的ReactNativeHost的实现:

* getUseDeveloperSupport 

	抽象方法,用来控制RN调试开关的,一般直接复用BuildConfig.DEBUG开关就行,如果有冲突就自行新建一个buildConfigField(如这里的BuildConfig.REACT_DEBUG).
* getPackages

	用于指定JS和native通信的ReactPackage,在ReactPackage中可以指定native和JS通信的一些module.其中MainReactPackage是RN已经封装好一些native module和view manager等.
* getJSBundleFile

	用于ReactNativeHost创建ReactInstanceManager时指定对应的本地JS bundle文件路径.如果返回null,则从getBundleAssetName接口取assets中的对应文件(一般仅用于调试).

接下来我们看看为什么要用维护<bundlePath,ReactNativeHost>映射map的方式来实现多个RN模块的切换.

# ReactActivity

当RN页面构建的时候,RN提供了ReactActivity组件来展示页面.值得一提的是,ReactActivity是一个抽象类,但是此类中没有抽象方法,像getMainComponentName这样需要子类中实现的方法却没有加抽象标识,这应该是facebook的RN团队疏忽了.在ReactActivity类中,可以看到以下代码:

```
private final ReactActivityDelegate mDelegate = this.createReactActivityDelegate();

protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        this.mDelegate.onCreate(savedInstanceState);
    }
```
这里createReactActivityDelegate时,会将ReactActivity中指定的RN模块名(即getMainComponentName)传入ReactActivityDelegate,紧接着是调用ReactActivityDelegate对应的生命周期onCreate,来看看里面都做了些什么:

```
protected void onCreate(Bundle savedInstanceState) {
        if(this.getReactNativeHost().getUseDeveloperSupport() && VERSION.SDK_INT >= 23 && !Settings.canDrawOverlays(this.getContext())) {
            Intent serviceIntent = new Intent("android.settings.action.MANAGE_OVERLAY_PERMISSION");
            this.getContext().startActivity(serviceIntent);
            FLog.w("React", "Overlay permissions needs to be granted in order for react native apps to run in dev mode");
            Toast.makeText(this.getContext(), "Overlay permissions needs to be granted in order for react native apps to run in dev mode", 1).show();
        }

        if(this.mMainComponentName != null) {
            this.loadApp(this.mMainComponentName);
        }

        this.mDoubleTapReloadRecognizer = new DoubleTapReloadRecognizer();
    }
```
----
第一个if块中的代码很简单,就是当RN在调试模式下,针对系统在SDK23以上创建RN调试悬浮窗的权限判断,没有权限则请求用户授权.Android官方文档:
	
```
Note: If the app targets API level 23 or higher, the app user must explicitly grant this permission to the app through a permission management screen. The app requests
 the user's approval by sending an intent with action 
ACTION_MANAGE_OVERLAY_PERMISSION. The app can check whether it has this authorization by calling

Settings.canDrawOverlays().
```
----
第二个if块是最关键的.通过ReactActivityDelegate来loadApp,这也是最耗时的操作,展现RN页面慢/白屏的根源.这里主要是创建ReactRootView以及初始化React上下文环境.

```
protected void loadApp(String appKey) {
        if(this.mReactRootView != null) {
            throw new IllegalStateException("Cannot loadApp while app is already running.");
        } else {
            this.mReactRootView = this.createRootView();
            this.mReactRootView.startReactApplication(this.getReactNativeHost().getReactInstanceManager(), appKey, this.getLaunchOptions());
            this.getPlainActivity().setContentView(this.mReactRootView);
        }
    }
```
如何优化RN的性能和展现效率,主要就是针对这一个耗时方法进行优化即可.可以对ReactRootView进行缓存管理以及将创建React上下文环境提前预处理.
我们来看看上面的遗留问题----为什么要用维护<bundlePath,ReactNativeHost>映射map的方式来实现多个RN模块的切换.在启动RN应用时startReactApplication需要传入ReactNativeHost中的ReactInstanceManager对象,我们来看看源码(ReactNativeHost.java):

```
public ReactInstanceManager getReactInstanceManager() {
        if(this.mReactInstanceManager == null) {
            this.mReactInstanceManager = this.createReactInstanceManager();
        }

        return this.mReactInstanceManager;
    }

protected ReactInstanceManager createReactInstanceManager() {
        Builder builder = ReactInstanceManager.builder().setApplication(this.mApplication).setJSMainModuleName(this.getJSMainModuleName()).setUseDeveloperSupport(this.getUseDeveloperSupport()).setRedBoxHandler(this.getRedBoxHandler()).setUIImplementationProvider(this.getUIImplementationProvider()).setInitialLifecycleState(LifecycleState.BEFORE_CREATE);
        Iterator jsBundleFile = this.getPackages().iterator();

        while(jsBundleFile.hasNext()) {
            ReactPackage reactPackage = (ReactPackage)jsBundleFile.next();
            builder.addPackage(reactPackage);
        }

        String jsBundleFile1 = this.getJSBundleFile();
        if(jsBundleFile1 != null) {
            builder.setJSBundleFile(jsBundleFile1);
        } else {
            builder.setBundleAssetName((String)Assertions.assertNotNull(this.getBundleAssetName()));
        }

        return builder.build();
    }
```
可以发现,ReactNativeHost中的ReactInstanceManager只在创建时读取bundle路径等信息.也就约等于一个ReactNativeHost对应一个bundle入口文件.这就是为什么我们以维护一个<bundlePath,ReactNativeHost>映射map的方式来实现native app中多个RN模块的切换.

继续来看看创建React上下文环境的实现逻辑(XReactInstanceManagerImpl.java):

```
public void createReactContextInBackground() {
        Assertions.assertCondition(!this.mHasStartedCreatingInitialContext, "createReactContextInBackground should only be called when creating the react application for the first time. When reloading JS, e.g. from a new file, explicitlyuse recreateReactContextInBackground");
        this.mHasStartedCreatingInitialContext = true;
        this.recreateReactContextInBackgroundInner();
    }
private void recreateReactContextInBackgroundInner() {
        UiThreadUtil.assertOnUiThread();
        if(this.mUseDeveloperSupport && this.mJSMainModuleName != null) {
            final DeveloperSettings devSettings = this.mDevSupportManager.getDevSettings();
            if(this.mDevSupportManager.hasUpToDateJSBundleInCache() && !devSettings.isRemoteJSDebugEnabled()) {
                this.onJSBundleLoadedFromServer();
            } else if(this.mBundleLoader == null) {
                this.mDevSupportManager.handleReloadJS();
            } else {
                this.mDevSupportManager.isPackagerRunning(new PackagerStatusCallback() {
                    public void onPackagerStatusFetched(final boolean packagerIsRunning) {
                        UiThreadUtil.runOnUiThread(new Runnable() {
                            public void run() {
                                if(packagerIsRunning) {
                                    XReactInstanceManagerImpl.this.mDevSupportManager.handleReloadJS();
                                } else {
                                    devSettings.setRemoteJSDebugEnabled(false);
                                    XReactInstanceManagerImpl.this.recreateReactContextInBackgroundFromBundleLoader();
                                }

                            }
                        });
                    }
                });
            }

        } else {
            this.recreateReactContextInBackgroundFromBundleLoader();
        }
    }
```
第二个if块的关键代码就分析到这.

----
最后一句是调试模式下,注册一个DoubleTapReloadRecognizer,按两下R键重新加载bundle.处理逻辑是在DevSupportManager(通过DevSupportManagerFactory.create创建)的handleReloadJS方法中处理的.最终实现逻辑(XReactInstanceManagerImpl.java):

```
private void recreateReactContextInBackground(com.facebook.react.cxxbridge.JavaScriptExecutor.Factory jsExecutorFactory, JSBundleLoader jsBundleLoader) {
        UiThreadUtil.assertOnUiThread();
        XReactInstanceManagerImpl.ReactContextInitParams initParams = new XReactInstanceManagerImpl.ReactContextInitParams(jsExecutorFactory, jsBundleLoader);
        if(this.mReactContextInitAsyncTask == null) {
            this.mReactContextInitAsyncTask = new XReactInstanceManagerImpl.ReactContextInitAsyncTask(null);
            this.mReactContextInitAsyncTask.executeOnExecutor(AsyncTask.THREAD_POOL_EXECUTOR, new XReactInstanceManagerImpl.ReactContextInitParams[]{initParams});
        } else {
            this.mPendingReactContextInitParams = initParams;
        }

    }
```

# bundle管理
![](/static/bundleManage.png)

主要根据以上流程实现即可,同时要兼具安全性考量.验证文件安全性.

 


