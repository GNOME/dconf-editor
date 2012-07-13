nm --dynamic --defined-only libdconfsettings.so > public-abi
test "`cat public-abi | cut -f 3 -d ' ' | grep -v ^_ | grep -v ^g_io_module | wc -l`" -eq 0 && rm public-abi
