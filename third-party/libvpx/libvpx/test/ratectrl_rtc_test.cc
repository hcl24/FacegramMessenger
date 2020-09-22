/*
 *  Copyright (c) 2020 The WebM project authors. All Rights Reserved.
 *
 *  Use of this source code is governed by a BSD-style license
 *  that can be found in the LICENSE file in the root of the source
 *  tree. An additional intellectual property rights grant can be found
 *  in the file PATENTS.  All contributing project authors may
 *  be found in the AUTHORS file in the root of the source tree.
 */
#include "vp9/ratectrl_rtc.h"

#include <fstream>  // NOLINT
#include <string>

#include "./vpx_config.h"
#include "third_party/googletest/src/include/gtest/gtest.h"
#include "test/codec_factory.h"
#include "test/encode_test_driver.h"
#include "test/util.h"
#include "test/video_source.h"
#include "vpx/vpx_codec.h"
#include "vpx_ports/bitops.h"

namespace {

const size_t kNumFrame = 850;

struct FrameInfo {
  friend std::istream &operator>>(std::istream &is, FrameInfo &info) {
    is >> info.frame_id >> info.spatial_id >> info.temporal_id >> info.base_q >>
        info.target_bandwidth >> info.buffer_level >> info.filter_level_ >>
        info.bytes_used;
    return is;
  }
  int frame_id;
  int spatial_id;
  int temporal_id;
  // Base QP
  int base_q;
  size_t target_bandwidth;
  size_t buffer_level;
  // Loopfilter level
  int filter_level_;
  // Frame size for current frame, used for pose encode update
  size_t bytes_used;
};

// This test runs the rate control interface and compare against ground truth
// generated by encoders.
// Settings for the encoder:
// For 1 layer:
//
// examples/vpx_temporal_svc_encoder gipsrec_motion1.1280_720.yuv out vp9
//    1280 720 1 30 7 0 0 1 0 1000
//
// For SVC (3 temporal layers, 3 spatial layers):
//
// examples/vp9_spatial_svc_encoder -f 10000 -w 1280 -h 720 -t 1/30 -sl 3
// -k 10000 -bl 100,140,200,250,350,500,450,630,900 -b 1600 --rc-end-usage=1
// --lag-in-frames=0 --passes=1 --speed=7 --threads=1
// --temporal-layering-mode=3 -aq 1 -rcstat 1
// gipsrec_motion1.1280_720.yuv -o out.webm
//
// - AQ_Mode 0
// - Disable golden refresh
// - Bitrate x 2 at frame/superframe 200
// - Bitrate / 4 at frame/superframe 400
//
// The generated file includes:
// frame number, spatial layer ID, temporal layer ID, base QP, target
// bandwidth, buffer level, loopfilter level, encoded frame size
// TODO(jianj): Remove golden files, and run actual encoding in this test.
class RcInterfaceTest : public ::testing::Test {
 public:
  explicit RcInterfaceTest() {}

  virtual ~RcInterfaceTest() {}

 protected:
  void RunOneLayer() {
    SetConfigOneLayer();
    rc_api_->Create(rc_cfg_);
    FrameInfo frame_info;
    libvpx::VP9FrameParamsQpRTC frame_params;
    frame_params.frame_type = KEY_FRAME;
    frame_params.spatial_layer_id = 0;
    frame_params.temporal_layer_id = 0;
    std::ifstream one_layer_file;
    one_layer_file.open(libvpx_test::GetDataPath() +
                        "/rc_interface_test_one_layer");
    ASSERT_EQ(one_layer_file.rdstate() & std::ifstream::failbit, 0);
    for (size_t i = 0; i < kNumFrame; i++) {
      one_layer_file >> frame_info;
      if (frame_info.frame_id > 0) frame_params.frame_type = INTER_FRAME;
      if (frame_info.frame_id == 200) {
        rc_cfg_.target_bandwidth = rc_cfg_.target_bandwidth * 2;
        rc_api_->UpdateRateControl(rc_cfg_);
      } else if (frame_info.frame_id == 400) {
        rc_cfg_.target_bandwidth = rc_cfg_.target_bandwidth / 4;
        rc_api_->UpdateRateControl(rc_cfg_);
      }
      ASSERT_EQ(frame_info.spatial_id, 0);
      ASSERT_EQ(frame_info.temporal_id, 0);
      rc_api_->ComputeQP(frame_params);
      ASSERT_EQ(rc_api_->GetQP(), frame_info.base_q);
      ASSERT_EQ(rc_api_->GetLoopfilterLevel(), frame_info.filter_level_);
      rc_api_->PostEncodeUpdate(frame_info.bytes_used);
    }
  }

  void RunSVC() {
    SetConfigSVC();
    rc_api_->Create(rc_cfg_);
    FrameInfo frame_info;
    libvpx::VP9FrameParamsQpRTC frame_params;
    frame_params.frame_type = KEY_FRAME;
    std::ifstream svc_file;
    svc_file.open(std::string(std::getenv("LIBVPX_TEST_DATA_PATH")) +
                  "/rc_interface_test_svc");
    ASSERT_EQ(svc_file.rdstate() & std::ifstream::failbit, 0);
    for (size_t i = 0; i < kNumFrame * rc_cfg_.ss_number_layers; i++) {
      svc_file >> frame_info;
      if (frame_info.frame_id > 0) frame_params.frame_type = INTER_FRAME;
      if (frame_info.frame_id == 200 * rc_cfg_.ss_number_layers) {
        for (int layer = 0;
             layer < rc_cfg_.ss_number_layers * rc_cfg_.ts_number_layers;
             layer++)
          rc_cfg_.layer_target_bitrate[layer] *= 2;
        rc_cfg_.target_bandwidth *= 2;
        rc_api_->UpdateRateControl(rc_cfg_);
      } else if (frame_info.frame_id == 400 * rc_cfg_.ss_number_layers) {
        for (int layer = 0;
             layer < rc_cfg_.ss_number_layers * rc_cfg_.ts_number_layers;
             layer++)
          rc_cfg_.layer_target_bitrate[layer] /= 4;
        rc_cfg_.target_bandwidth /= 4;
        rc_api_->UpdateRateControl(rc_cfg_);
      }
      frame_params.spatial_layer_id = frame_info.spatial_id;
      frame_params.temporal_layer_id = frame_info.temporal_id;
      rc_api_->ComputeQP(frame_params);
      ASSERT_EQ(rc_api_->GetQP(), frame_info.base_q);
      ASSERT_EQ(rc_api_->GetLoopfilterLevel(), frame_info.filter_level_);
      rc_api_->PostEncodeUpdate(frame_info.bytes_used);
    }
  }

 private:
  void SetConfigOneLayer() {
    rc_cfg_.width = 1280;
    rc_cfg_.height = 720;
    rc_cfg_.max_quantizer = 52;
    rc_cfg_.min_quantizer = 2;
    rc_cfg_.target_bandwidth = 1000;
    rc_cfg_.buf_initial_sz = 600;
    rc_cfg_.buf_optimal_sz = 600;
    rc_cfg_.buf_sz = 1000;
    rc_cfg_.undershoot_pct = 50;
    rc_cfg_.overshoot_pct = 50;
    rc_cfg_.max_intra_bitrate_pct = 1000;
    rc_cfg_.framerate = 30.0;
    rc_cfg_.ss_number_layers = 1;
    rc_cfg_.ts_number_layers = 1;
    rc_cfg_.scaling_factor_num[0] = 1;
    rc_cfg_.scaling_factor_den[0] = 1;
    rc_cfg_.layer_target_bitrate[0] = 1000;
    rc_cfg_.max_quantizers[0] = 52;
    rc_cfg_.min_quantizers[0] = 2;
  }

  void SetConfigSVC() {
    rc_cfg_.width = 1280;
    rc_cfg_.height = 720;
    rc_cfg_.max_quantizer = 56;
    rc_cfg_.min_quantizer = 2;
    rc_cfg_.target_bandwidth = 1600;
    rc_cfg_.buf_initial_sz = 500;
    rc_cfg_.buf_optimal_sz = 600;
    rc_cfg_.buf_sz = 1000;
    rc_cfg_.undershoot_pct = 50;
    rc_cfg_.overshoot_pct = 50;
    rc_cfg_.max_intra_bitrate_pct = 900;
    rc_cfg_.framerate = 30.0;
    rc_cfg_.ss_number_layers = 3;
    rc_cfg_.ts_number_layers = 3;

    rc_cfg_.scaling_factor_num[0] = 1;
    rc_cfg_.scaling_factor_den[0] = 4;
    rc_cfg_.scaling_factor_num[1] = 2;
    rc_cfg_.scaling_factor_den[1] = 4;
    rc_cfg_.scaling_factor_num[2] = 4;
    rc_cfg_.scaling_factor_den[2] = 4;

    rc_cfg_.ts_rate_decimator[0] = 4;
    rc_cfg_.ts_rate_decimator[1] = 2;
    rc_cfg_.ts_rate_decimator[2] = 1;

    rc_cfg_.layer_target_bitrate[0] = 100;
    rc_cfg_.layer_target_bitrate[1] = 140;
    rc_cfg_.layer_target_bitrate[2] = 200;
    rc_cfg_.layer_target_bitrate[3] = 250;
    rc_cfg_.layer_target_bitrate[4] = 350;
    rc_cfg_.layer_target_bitrate[5] = 500;
    rc_cfg_.layer_target_bitrate[6] = 450;
    rc_cfg_.layer_target_bitrate[7] = 630;
    rc_cfg_.layer_target_bitrate[8] = 900;

    for (int sl = 0; sl < rc_cfg_.ss_number_layers; ++sl) {
      for (int tl = 0; tl < rc_cfg_.ts_number_layers; ++tl) {
        const int i = sl * rc_cfg_.ts_number_layers + tl;
        rc_cfg_.max_quantizers[i] = 56;
        rc_cfg_.min_quantizers[i] = 2;
      }
    }
  }

  std::unique_ptr<libvpx::VP9RateControlRTC> rc_api_;
  libvpx::VP9RateControlRtcConfig rc_cfg_;
};

TEST_F(RcInterfaceTest, OneLayer) { RunOneLayer(); }

TEST_F(RcInterfaceTest, SVC) { RunSVC(); }
}  // namespace

int main(int argc, char **argv) {
  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
