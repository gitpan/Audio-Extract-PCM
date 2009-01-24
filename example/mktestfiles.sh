#!/bin/sh

# This shows how you can make a test sound file

# Sine tone
sox -n foo1.wav synth 0:10 sine 2000

# Create a four-channel file
sox -n -c4 foo2.wav synth 0:10 sine 2000
