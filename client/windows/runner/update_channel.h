#pragma once
#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <memory>
#include <windows.h>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> CreateUpdateChannel(flutter::BinaryMessenger* messenger, HWND window);
