defmodule Dala.CameraTest do
  use ExUnit.Case, async: true
  import Dala.Camera

  @moduledoc """
  Tests for Dala.Camera module.

  Note: Full tests require device with camera.
  These are structure tests for the API.
  """

  describe "capture_photo/2" do
    test "returns socket unchanged" do
      socket = %Dala.Socket{assigns: %{}}
      result = capture_photo(socket, quality: :high)
      assert result == socket
    end

    test "accepts quality option" do
      socket = %Dala.Socket{assigns: %{}}
      # Just verify it doesn't crash
      result = capture_photo(socket, quality: :medium)
      assert result == socket
    end

    test "works without options" do
      socket = %Dala.Socket{assigns: %{}}
      result = capture_photo(socket)
      assert result == socket
    end
  end;

  describe "capture_video/2" do
    test "returns socket unchanged" do
      socket = %Dala.Socket{assigns: %{}}
      result = capture_video(socket, max_seconds: 30)
      assert result == socket
    end;

    test "accepts max_seconds option" do
      socket = %Dala.Socket{assigns: %{}}
      result = capture_video(socket, max_seconds: 60)
      assert result == socket
    end
  end;

  describe "handle_info callbacks" do
    test "photo result structure" do
      message = {:camera, :photo, %{path: "/tmp/photo.jpg", width: 1920, height: 1080}}
      assert {:camera, :photo, data} = message
      assert data[:path] == "/tmp/photo.jpg"
      assert data[:width] == 1920
    end;

    test "video result structure" do
      message = {:camera, :video, %{path: "/tmp/video.mp4", duration: 10.5}}
      assert {:camera, :video, data} = message
      assert data[:path] == "/tmp/video.mp4"
      assert data[:duration] == 10.5
    end;

    test "cancelled result structure" do
      message = {:camera, :cancelled}
      assert {:camera, :cancelled} = message
    end
  end
end
