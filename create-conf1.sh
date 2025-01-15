#!/usr/bin/env bash

rm -rf conf

mkdir conf
cd conf || exit 0
git init
echo -e "hello world\n\nhello unchanged\n\nthis is changes on\nmulti\nlines" >file1.txt
git add file1.txt
git commit -m "batman"
git branch changes
echo -e "hello change\n\nhello unchanged\n\nthis is nothing on\nmultdsajsjahi\nldsjadjshines" >file1.txt
git add file1.txt
git commit -m "change1"
git switch changes
echo -e "hello diff\n\nhello unchanged\n\nthis is something on\nkdjsshajhdsaj\nhiendline" >file1.txt
git add file1.txt
git commit -m "change2"
git merge master
