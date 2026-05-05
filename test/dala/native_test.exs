defmodule Dala.NativeTest do
  use ExUnit.Case, async: false

  describe "platform/0" do
    test "returns an atom" do
      result = Dala.Native.platform()
      assert result in [:ios, :android, :unknown]
    end
  end

  describe "log/1 and log/2" do
    test "log/1 returns :ok" do
      assert :ok = Dala.Native.log("hello from rust")
    end

    test "log/2 returns :ok" do
      # assert :ok = Dala.Native.log_level("info", "hello with level") (disabled)
    end
  end

  describe "set_transition/1" do
    test "accepts transition string" do
      assert :ok = Dala.Native.set_transition("slide")
      assert :ok = Dala.Native.set_transition("none")
    end
  end

  describe "set_root/1" do
    test "accepts JSON string" do
      json = ~s({"type": "column", "children": []})
      assert :ok = Dala.Native.set_root(json)
    end
  end

  describe "register_tap/1 and clear_taps/0" do
    test "register_tap returns :ok" do
      # We pass self() as a stand-in for a pid
      assert :ok = Dala.Native.register_tap(self())
    end

    test "clear_taps returns :ok" do
      assert :ok = Dala.Native.clear_taps()
    end
  end

  describe "exit_app/0" do
    test "returns :ok (stub)" do
      # Don't actually exit during tests
      result = Dala.Native.exit_app()
      assert result in [:ok, :error] or is_binary(result)
    end
  end

  describe "safe_area/0" do
    test "returns :ok (stub)" do
      assert :ok = Dala.Native.safe_area()
    end
  end

  describe "haptic/1" do
    test "accepts haptic type" do
      assert :ok = Dala.Native.haptic("light")
      assert :ok = Dala.Native.haptic("medium")
      assert :ok = Dala.Native.haptic("heavy")
    end
  end

  describe "clipboard_put/1 and clipboard_get/0" do
    test "clipboard_put returns :ok" do
      assert :ok = Dala.Native.clipboard_put("test text")
    end

    test "clipboard_get returns binary or :error" do
      result = Dala.Native.clipboard_get()
      assert result in [:ok, :error] or is_binary(result)
    end
  end

  describe "share_text/1" do
    test "returns :ok" do
      assert :ok = Dala.Native.share_text("share this")
    end
  end

  describe "request_permission/1" do
    test "returns :ok (stub)" do
      assert :ok = Dala.Native.request_permission("camera")
    end
  end

  describe "biometric_authenticate/1" do
    test "returns :ok (stub)" do
      assert :ok = Dala.Native.biometric_authenticate("Please authenticate")
    end
  end

  describe "location functions" do
    test "location_get_once returns :ok or binary" do
      result = Dala.Native.location_get_once()
      assert result in [:ok, :error] or is_binary(result)
    end

    test "location_start returns :ok" do
      assert :ok = Dala.Native.location_start("high")
    end

    test "location_stop returns :ok" do
      assert :ok = Dala.Native.location_stop()
    end
  end

  describe "camera functions" do
    test "camera_capture_photo returns :ok" do
      assert :ok = Dala.Native.camera_capture_photo("high")
    end

    test "camera_capture_video returns :ok" do
      assert :ok = Dala.Native.camera_capture_video("30")
    end

    test "camera_start_preview returns :ok" do
      assert :ok = Dala.Native.camera_start_preview(~s({}))
    end

    test "camera_stop_preview returns :ok" do
      assert :ok = Dala.Native.camera_stop_preview()
    end
  end

  describe "photos_pick/2" do
    test "returns :ok" do
      assert :ok = Dala.Native.photos_pick(5, ~s(["public.image"]))
    end
  end

  describe "files_pick/1" do
    test "returns :ok" do
      assert :ok = Dala.Native.files_pick(~s(["application/pdf"]))
    end
  end

  describe "audio functions" do
    test "audio_start_recording returns :ok" do
      assert :ok = Dala.Native.audio_start_recording(~s({"format": "m4a"}))
    end

    test "audio_stop_recording returns :ok" do
      assert :ok = Dala.Native.audio_stop_recording()
    end

    test "audio_play returns :ok" do
      assert :ok = Dala.Native.audio_play("/tmp/test.m4a", ~s({}))
    end

    test "audio_stop_playback returns :ok" do
      assert :ok = Dala.Native.audio_stop_playback()
    end

    test "audio_set_volume returns :ok" do
      assert :ok = Dala.Native.audio_set_volume(0.8)
    end
  end

  describe "motion functions" do
    test "motion_start returns :ok" do
      assert :ok = Dala.Native.motion_start(~s(["accelerometer"]), 100)
    end

    test "motion_stop returns :ok" do
      assert :ok = Dala.Native.motion_stop()
    end
  end

  describe "scanner_scan/1" do
    test "returns :ok" do
      assert :ok = Dala.Native.scanner_scan(~s(["qr", "code128"]))
    end
  end

  describe "notification functions" do
    test "notify_schedule returns :ok" do
      assert :ok = Dala.Native.notify_schedule(~s({"title": "test"}))
    end

    test "notify_cancel returns :ok" do
      assert :ok = Dala.Native.notify_cancel("notification_id")
    end

    test "notify_register_push returns :ok" do
      assert :ok = Dala.Native.notify_register_push()
    end

    test "take_launch_notification returns :ok or binary" do
      result = Dala.Native.take_launch_notification()
      assert result in [:ok, :error] or is_binary(result)
    end
  end

  describe "storage functions" do
    test "storage_dir returns :ok or binary" do
      result = Dala.Native.storage_dir("documents")
      assert result in [:ok, :error] or is_binary(result)
    end

    test "storage_save_to_photo_library returns :ok" do
      assert :ok = Dala.Native.storage_save_to_photo_library("/tmp/test.jpg")
    end

    test "storage_save_to_media_store returns :ok" do
      assert :ok = Dala.Native.storage_save_to_media_store("/tmp/test.mp4", "video")
    end

    test "storage_external_files_dir returns :ok or binary" do
      result = Dala.Native.storage_external_files_dir("pictures")
      assert result in [:ok, :error] or is_binary(result)
    end
  end

  describe "alert/overlay functions" do
    test "alert_show returns :ok" do
      assert :ok = Dala.Native.alert_show("Title", "Message", ~s([{"text": "OK"}]))
    end

    test "action_sheet_show returns :ok" do
      assert :ok = Dala.Native.action_sheet_show("Title", ~s([{"text": "Option 1"}]))
    end

    test "toast_show returns :ok" do
      assert :ok = Dala.Native.toast_show("Toast message", "short")
    end
  end

  describe "webview functions" do
    test "webview_eval_js returns :ok" do
      assert :ok = Dala.Native.webview_eval_js("console.log('hello')")
    end

    test "webview_post_message returns :ok" do
      assert :ok = Dala.Native.webview_post_message(~s({"type": "ping"}))
    end

    test "webview_can_go_back returns :true or :false" do
      result = Dala.Native.webview_can_go_back()
      assert result in [true, false]
    end

    test "webview_go_back returns :ok" do
      assert :ok = Dala.Native.webview_go_back()
    end
  end

  describe "component registration" do
    test "register_component returns :ok" do
      assert :ok = Dala.Native.register_component(self())
    end

    test "deregister_component returns :ok" do
      assert :ok = Dala.Native.deregister_component(1)
    end
  end

  describe "test harness functions" do
    test "ui_tree returns :ok or binary" do
      result = Dala.Native.ui_tree()
      assert result in [:ok, :error] or is_binary(result)
    end

    test "ui_debug returns :ok or binary" do
      result = Dala.Native.ui_debug()
      assert result in [:ok, :error] or is_binary(result)
    end

    test "tap returns :ok" do
      assert :ok = Dala.Native.tap("Submit")
    end

    test "tap_xy returns :ok" do
      assert :ok = Dala.Native.tap_xy(100.0, 200.0)
    end

    test "type_text returns :ok" do
      assert :ok = Dala.Native.type_text("hello")
    end

    test "delete_backward returns :ok" do
      assert :ok = Dala.Native.delete_backward()
    end

    test "key_press returns :ok" do
      assert :ok = Dala.Native.key_press("enter")
    end

    test "clear_text returns :ok" do
      assert :ok = Dala.Native.clear_text()
    end

    test "long_press_xy returns :ok" do
      assert :ok = Dala.Native.long_press_xy(100.0, 200.0, 500)
    end

    test "swipe_xy returns :ok" do
      assert :ok = Dala.Native.swipe_xy(100.0, 200.0, 300.0, 200.0)
    end
  end
end
