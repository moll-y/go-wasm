module github.com/johnstarich/go-wasm

go 1.13

require (
	github.com/pkg/errors v0.9.1
	github.com/spf13/afero v1.3.0
	github.com/stretchr/testify v1.4.0
	go.uber.org/atomic v1.6.0
)

replace github.com/spf13/afero v1.3.0 => github.com/johnstarich/afero v1.3.2-0.20200804030734-3ceac0d6c4a1
