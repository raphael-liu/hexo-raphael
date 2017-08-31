---
title: Android自定义锁屏页
date: 2017-08-29 18:47:59
tags: Android
reward: true
---
# 自定义锁屏页的使用场景
* 音乐类应用需要在不解锁的情况下，显示音乐相关信息，以及控制音乐播放相关操作。
* 资讯类应用需要在不解锁的情况下，显示资讯推送信息，方便用户及时阅读。
* 其他应用需要在锁屏页展示应用信息。

# 自定义锁屏页的基本原理
Android系统实现自定义锁屏页的思路很简单：在App启动时开启一个service，在Service中监听系统SCREEN\_OFF的广播，当屏幕熄灭锁屏时，Service会监听到系统广播，开启一个锁屏页Activity在屏幕最上层显示，该Activity创建的同时会去掉系统锁屏。流程图如下：
<!-- more -->

![](/static/lockScreen.png)
## 注册广播
在应用启动时，直接startService。

	Intent intent = new Intent(getApplicationContext(),LockScreenService.class);
	startService(intent);

而在service中，我们需要动态注册监听SCREEN\_OFF广播，而在AndroidManifest.xml中静态注册的广播将无法接受到SCREEN\_OFF广播，这在官方文档中有明确说明：

```
ACTION_SCREEN_OFF

added in API level 1
String ACTION_SCREEN_OFF
Broadcast Action: Sent when the device goes to sleep and becomes non-interactive.

For historical reasons, the name of this broadcast action refers to the power state of the screen but it is actually sent in response to changes in the overall interactive state of the device.

This broadcast is sent when the device becomes non-interactive which may have nothing to do with the screen turning off. To determine the actual state of the screen, use getState().

See isInteractive() for details.

You cannot receive this through components declared in manifests, only by explicitly registering for it with Context.registerReceiver().
This is a protected intent that can only be sent by the system.

Constant Value: "android.intent.action.SCREEN_OFF"
```
因此我们通过如下代码来进行注册监听广播：

	public class LockScreenService extends Service {

    	private BroadcastReceiver mScreenOffReceiver = new BroadcastReceiver() {
        	@Override
        	public void onReceive(Context context, Intent intent) {
            	if (intent.getAction().equals(Intent.ACTION_SCREEN_OFF)) {
                	Intent in = new Intent(context, SecondActivity.class);
                	in.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS);
                	startActivity(in);
            	}
        	}
    	};

    	@Override
    	public void onCreate() {
        	super.onCreate();

        	IntentFilter screenOffFilter = new IntentFilter();
        	screenOffFilter.addAction(Intent.ACTION_SCREEN_OFF);
        	registerReceiver(mScreenOffReceiver,screenOffFilter);

    	}

    	@Nullable
    	@Override
    	public IBinder onBind(Intent intent) {
        	return null;
    	}

    	@Override
    	public void onDestroy() {
        	super.onDestroy();
        	unregisterReceiver(mScreenOffReceiver);
    	}
	}
这里有必要说下启动锁屏页Activity的intent的flag，如果不添加Intent.FLAG\_ACTIVITY\_NEW\_TASK时，会出现“Calling startActivity() from outside of an Activity”的运行时异常，毕竟我们是从Service启动的Activity。Activity要存在于activity的栈中，而Service在启动activity时必然不存在一个activity的栈，所以要新起一个栈，并装入启动的activity。使用该标志位时，也需要在AndroidManifest中声明taskAffinity，即新task的名称，否则锁屏Activity实质上还是在建立在原来App的task栈中。而Intent.FLAG\_ACTIVITY\_EXCLUDE\_FROM\_RECENTS是为了避免在最近使用程序列表出现Service所启动的Activity,但这个标志位不是必须的，其使用依情况而定。

## 自定义锁屏页Activity设置
直接边看代码边说吧：

	public class SecondActivity extends BaseActivity {
    	@Override
    	protected void onCreate(@Nullable Bundle savedInstanceState) {
        	super.onCreate(savedInstanceState);
        	getWindow().addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                | WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD);

        	setContentView(R.layout.activity_second);
        	setTitle("SecondActivity");

    	}

		@Override
    	public boolean onKeyDown(int keyCode, KeyEvent event) {
        	int key = event.getKeyCode();
        	switch (key) {
            	case KeyEvent.KEYCODE_BACK: {
               		return true;
            	}
            	case KeyEvent.KEYCODE_MENU: {
                	return true;
            	}

        	}
        	return super.onKeyDown(keyCode, event);
    	}

	}

在自定义锁屏页中，我们需要设置FLAG\_SHOW\_WHEN\_LOCKED标识来让activity在锁屏的时候能够显示，同时设置FLAG\_DISMISS\_KEYGUARD标识来去掉系统锁屏，当然如果设置了系统锁屏密码则无法去掉系统锁屏。不要忘记在AndroidManifest.xml中加入对应权限：

	<uses-permission android:name="android.permission.DISABLE_KEYGUARD"/>
我们来看下锁屏时候的展示效果：

![](/static/screenLockShot.jpg)

我们后期可以做一些扩展，比如屏蔽某些按键，增加滑屏解锁，这些就不在这赘述了。




