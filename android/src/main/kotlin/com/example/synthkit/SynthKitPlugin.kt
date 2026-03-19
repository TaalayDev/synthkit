package com.example.synthkit

import io.flutter.embedding.engine.plugins.FlutterPlugin

class SynthKitPlugin : FlutterPlugin {
    companion object {
        init {
            System.loadLibrary("synthkit_android")
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {}

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
