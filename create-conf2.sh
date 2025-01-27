#!/usr/bin/env bash

rm -rf conf

mkdir conf
cd conf || exit 0
git init

echo -e "local function say_hello()\n  print('Hello, World!')\nend\n-- Call the function\nsay_hello()" >hello.lua
git add hello.lua
mkdir folder
cd folder
echo -e "this\n\nis\n\na\n\nlong\n\nsentence" >world.lua
git add world.lua
cd ..
git commit -m "batman"

git branch changes
echo -e "local function say_change()\n  print('Hello, change!')\nend\n-- Call the function\nsay_change()" >hello.lua
git add hello.lua
cd folder
echo -e "different\n\nwords\n\nin\n\na\n\nsequence" >world.lua
git add world.lua
cd ..
git commit -m "change1"

git switch changes
echo -e "local function say_name(name)\n  print('Hello,' .. name .. '!')\nend\n-- Call the function\nsay_name('Dylan')" >hello.lua
git add hello.lua
cd folder
echo -e "another\n\nvery\n\nvery\n\nlengthy\n\nstring" >world.lua
git add world.lua
cd ..
git commit -m "change2"

git merge master
