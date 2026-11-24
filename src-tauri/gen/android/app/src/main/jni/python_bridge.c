// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

#include <jni.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

typedef void (*PyInitializeFn)(void);
typedef void *(*PyEvalSaveThreadFn)(void);
typedef int (*PyRunSimpleStringFlagsFn)(const char *, void *);
typedef int (*PyGILStateEnsureFn)(void);
typedef void (*PyGILStateReleaseFn)(int);

typedef struct {
    void *library;
    PyInitializeFn initialize;
    PyEvalSaveThreadFn save_thread;
    PyRunSimpleStringFlagsFn run_string;
    PyGILStateEnsureFn gil_ensure;
    PyGILStateReleaseFn gil_release;
    char *home;
} PythonApi;

static PythonApi python_api;
static pthread_mutex_t python_mutex = PTHREAD_MUTEX_INITIALIZER;

static int load_python(const char *library_path, const char *python_home) {
    if (python_api.library != NULL) {
        return strcmp(python_api.home, python_home) == 0 ? 0 : -2;
    }

    if (setenv("PYTHONHOME", python_home, 1) != 0 ||
        setenv("PYTHONUTF8", "1", 1) != 0 ||
        setenv("PYTHONNOUSERSITE", "1", 1) != 0) {
        return -3;
    }

    python_api.library = dlopen(library_path, RTLD_NOW | RTLD_GLOBAL);
    if (python_api.library == NULL) {
        return -4;
    }

    python_api.initialize = (PyInitializeFn)dlsym(python_api.library, "Py_Initialize");
    python_api.save_thread = (PyEvalSaveThreadFn)dlsym(python_api.library, "PyEval_SaveThread");
    python_api.run_string = (PyRunSimpleStringFlagsFn)dlsym(python_api.library, "PyRun_SimpleStringFlags");
    python_api.gil_ensure = (PyGILStateEnsureFn)dlsym(python_api.library, "PyGILState_Ensure");
    python_api.gil_release = (PyGILStateReleaseFn)dlsym(python_api.library, "PyGILState_Release");
    if (python_api.initialize == NULL || python_api.save_thread == NULL ||
        python_api.run_string == NULL || python_api.gil_ensure == NULL ||
        python_api.gil_release == NULL) {
        dlclose(python_api.library);
        memset(&python_api, 0, sizeof(python_api));
        return -5;
    }

    python_api.home = strdup(python_home);
    if (python_api.home == NULL) {
        dlclose(python_api.library);
        memset(&python_api, 0, sizeof(python_api));
        return -6;
    }

    python_api.initialize();
    python_api.save_thread();
    return 0;
}

JNIEXPORT jint JNICALL
Java_com_zownload_app_NativePythonBridge_run(JNIEnv *env, jclass type,
                                              jstring library_path,
                                              jstring python_home,
                                              jstring source) {
    (void)type;
    if (library_path == NULL || python_home == NULL || source == NULL) {
        return -1;
    }

    const char *library = (*env)->GetStringUTFChars(env, library_path, NULL);
    const char *home = (*env)->GetStringUTFChars(env, python_home, NULL);
    const char *code = (*env)->GetStringUTFChars(env, source, NULL);
    if (library == NULL || home == NULL || code == NULL) {
        if (library != NULL) (*env)->ReleaseStringUTFChars(env, library_path, library);
        if (home != NULL) (*env)->ReleaseStringUTFChars(env, python_home, home);
        if (code != NULL) (*env)->ReleaseStringUTFChars(env, source, code);
        return -1;
    }

    pthread_mutex_lock(&python_mutex);
    int status = load_python(library, home);
    if (status == 0) {
        int gil = python_api.gil_ensure();
        status = python_api.run_string(code, NULL);
        python_api.gil_release(gil);
    }
    pthread_mutex_unlock(&python_mutex);

    (*env)->ReleaseStringUTFChars(env, library_path, library);
    (*env)->ReleaseStringUTFChars(env, python_home, home);
    (*env)->ReleaseStringUTFChars(env, source, code);
    return status;
}
