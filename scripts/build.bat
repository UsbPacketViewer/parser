@echo off
setlocal EnableDelayedExpansion
set xxx=
for %%s in (*.lua) do (
set xxx=!xxx! %%s
)
call luacc %xxx% %1 %2
