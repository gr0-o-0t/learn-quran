import 'dart:ffi';
import 'package:ffi/ffi.dart';

// Opaque types for llama.cpp structs
base class LlamaModel extends Opaque {}
base class LlamaContext extends Opaque {}

// C function signatures
typedef llama_backend_init_native = Void Function(Bool numa);
typedef llama_backend_init_dart = void Function(bool numa);

typedef llama_backend_free_native = Void Function();
typedef llama_backend_free_dart = void Function();

typedef llama_load_model_from_file_native = Pointer<LlamaModel> Function(
    Pointer<Utf8> pathModel,
    // For simplicity, we can pass a Pointer to a struct or ignore parameters by passing a dummy pointer
    Pointer<Void> params);
typedef llama_load_model_from_file_dart = Pointer<LlamaModel> Function(
    Pointer<Utf8> pathModel, Pointer<Void> params);

typedef llama_new_context_with_model_native = Pointer<LlamaContext> Function(
    Pointer<LlamaModel> model, Pointer<Void> params);
typedef llama_new_context_with_model_dart = Pointer<LlamaContext> Function(
    Pointer<LlamaModel> model, Pointer<Void> params);

typedef llama_free_native = Void Function(Pointer<LlamaContext> ctx);
typedef llama_free_dart = void Function(Pointer<LlamaContext> ctx);

typedef llama_free_model_native = Void Function(Pointer<LlamaModel> model);
typedef llama_free_model_dart = void Function(Pointer<LlamaModel> model);

class LlamaFfi {
  final DynamicLibrary _lib;

  late final llama_backend_init_dart backendInit;
  late final llama_backend_free_dart backendFree;
  late final llama_load_model_from_file_dart loadModelFromFile;
  late final llama_new_context_with_model_dart newContextWithModel;
  late final llama_free_dart freeContext;
  late final llama_free_model_dart freeModel;

  LlamaFfi(String libraryPath) : _lib = DynamicLibrary.open(libraryPath) {
    _initBindings();
  }

  void _initBindings() {
    backendInit = _lib
        .lookup<NativeFunction<llama_backend_init_native>>('llama_backend_init')
        .asFunction();

    backendFree = _lib
        .lookup<NativeFunction<llama_backend_free_native>>('llama_backend_free')
        .asFunction();

    loadModelFromFile = _lib
        .lookup<NativeFunction<llama_load_model_from_file_native>>(
            'llama_load_model_from_file')
        .asFunction();

    newContextWithModel = _lib
        .lookup<NativeFunction<llama_new_context_with_model_native>>(
            'llama_new_context_with_model')
        .asFunction();

    freeContext =
        _lib.lookup<NativeFunction<llama_free_native>>('llama_free').asFunction();

    freeModel = _lib
        .lookup<NativeFunction<llama_free_model_native>>('llama_free_model')
        .asFunction();
  }
}
