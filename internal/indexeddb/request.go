// +build js

package indexeddb

import (
	"runtime"
	"syscall/js"

	"github.com/johnstarich/go-wasm/internal/promise"
	"github.com/pkg/errors"
)

func processRequest(request js.Value) promise.Promise {
	resolve, reject, prom := promise.NewGo()

	var errFunc, successFunc js.Func
	errFunc = js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		err := request.Get("error")
		go reject(err)
		errFunc.Release()
		successFunc.Release()
		return nil
	})
	successFunc = js.FuncOf(func(this js.Value, args []js.Value) interface{} {
		result := request.Get("result")
		go resolve(result)
		errFunc.Release()
		successFunc.Release()
		return nil
	})
	request.Call("addEventListener", "error", errFunc)
	request.Call("addEventListener", "success", successFunc)
	return prom
}

func await(prom promise.Promise) (js.Value, error) {
	runtime.Gosched()
	val, err := prom.Await()
	if err != nil {
		return js.Value{}, err
	}
	return val.(js.Value), nil
}

func catch(err *error) {
	r := recover()
	if r == nil {
		return
	}
	switch val := r.(type) {
	case error:
		*err = val
	case js.Value:
		*err = js.Error{Value: val}
	default:
		*err = errors.Errorf("%+v", val)
	}
}
