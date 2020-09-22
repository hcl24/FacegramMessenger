# Copyright 2019 The Chromium Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

from recipe_engine import post_process

DEPS = ['gclient']

def RunSteps(api):
  src_cfg = api.gclient.make_config(CACHE_DIR='[ROOT]/git_cache')
  api.gclient.sync(src_cfg)

def GenTests(api):
  yield api.test(
      'no-json',
      api.override_step_data('gclient sync', retcode=1),
      # Should not fail with uncaught exception
      api.post_process(post_process.ResultReasonRE, r'^(?!Uncaught Exception)'),
      api.post_process(post_process.DropExpectation)
  )
