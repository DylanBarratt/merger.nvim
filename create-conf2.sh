#!/usr/bin/env bash

rm -rf conf

mkdir conf
cd conf || exit 0
git init
echo -e "local function say_hello()\nprint('Hello, World!')\nend\n-- Call the function\nsay_hello()" >hello.lua
git add hello.lua
git commit -m "batman"
git branch changes
echo -e "local function say_change()\nprint('Hello, change!')\nend\n-- Call the function\nsay_change()" >hello.lua
git add hello.lua
git commit -m "change1"
git switch changes
echo -e "local function say_name(name)\nprint('Hello,' .. name .. '!')\nend\n-- Call the function\nsay_name('Dylan')" >hello.lua
git add hello.lua
git commit -m "change2"
git merge master
