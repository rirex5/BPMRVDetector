//
//  BpmDetectService.swift
//  BPMRVDetector
//
//  Created by Atsushi Otsubo on 2017/09/29.
//  Copyright © 2017年 Rirex. All rights reserved.
//

import UIKit

import UIKit
import AudioToolbox
import MediaPlayer
import OpenAL

class BpmDetectService: NSObject {
    
    fileprivate let PI: Float = 3.14159265
    var matchData = "BPM, Match"
    
    /* メモリ解放用 */
    fileprivate func MyFreeOpenALAudioData(_ data: UnsafeMutablePointer<Int16>, _ dataSize: ALsizei) {
        let theData = UnsafeMutablePointer<Int16>?(data)
        if theData != nil {
            theData?.deallocate(capacity: Int(dataSize))
        }
    }
    
    /* ----------------------------------------------
     BPM取得の流れ
     getBpm                 : songIdを元に楽曲をメモリに読み込み、リニアPCM形式に変換してからBPMを取得する関数を呼び出す
     - createDiff           : 音量の増加量の差分を取り、リストに格納する
     - getRbpm              : 音量の増加量などを元に、BPMのマッチ度を計算してくれる
     - getBestMatchedBpm    : 最もマッチ度の大きいBPMを算出する
     ---------------------------------------------- */
    
    fileprivate func createDiff(_ src: [Int16], _ frameSize: Int, _ frameMax: Int) -> Array<Float> {
        var dst: [Float] = Array(repeating: 0.0, count: frameMax)
        var amp: [Float] = Array(repeating: 0.0, count: frameMax)
        for i in 0..<frameMax {
            for j in 0..<frameSize {
                amp[i] += Float(src[i * frameSize + j]) * Float(src[i * frameSize + j])
            }
            amp[i] = amp[i] / Float(frameSize)
        }
        for i in 0..<(frameMax-1) {
            dst[i] = max(amp[i+1] - amp[i], 0)
        }
        return dst
    }
    
    fileprivate func getRbpm(_ diff: [Float], _ fbpm: Float, _ fs: Float) -> Float {
        let N = diff.count
        var cosMatch: Float = 0, sinMatch: Float = 0
        // 音量の増加量リストを元にマッチ度を算出する
        for n in 0..<N {
            cosMatch = cosMatch + diff[n] * cos(2 * PI * fbpm * Float(n) / fs)
            sinMatch = sinMatch + diff[n] * sin(2 * PI * fbpm * Float(n) / fs)
        }
        let match = sqrt((cosMatch * cosMatch) + (sinMatch * sinMatch))
        return match
    }
    
    fileprivate func getBestMatchedBpmAndRV(_ diff: [Float], rate: Int, frameSize: Int) -> (bpm: Int, rv:Float)  {
        // マッチ度を算出するBPMの範囲を定義
        let lowerBpm = 60
        let upperBpm = 240
        
        var bpms: [Float] = Array(repeating: 0.0, count: upperBpm - lowerBpm + 1)
        var bpmValue = 0
        var bpmMatch : Float = 0.0
        // BPM60-300までの全てのマッチ度を取得し、もっともマッチ度の高いものを変数[bpmMatch]へ格納する
        for bpm in lowerBpm...upperBpm {
            bpms[bpm-lowerBpm] = getRbpm(diff, Float(bpm)/60.0, Float(rate)/Float(frameSize) )
            // print("\(String(format: "%d", bpm)) \(String(format: "%01f", bpms[bpm-lowerBpm])) ")
            if (bpmMatch < bpms[bpm-lowerBpm]) {
                bpmValue = bpm
                bpmMatch = bpms[bpm-lowerBpm]
            }
            matchData += "\n\(bpm),\(bpms[bpm-lowerBpm])"
        }
        // print("source bpm:\(bpmValue)")
        
        // RV計算
        let rv = getRV(bpms: bpms, bpmMatchMax: bpmMatch)
        
        // BPM80未満の場合はBPMを倍にする (ランニングやウォーキングでBPM80未満にはならいないため)
        //        if (bpmValue < 80) {
        //            bpmValue *= 2
        //            // BPMをより正確にするために補正する
        //            let index = bpmValue-lowerBpm
        //            if (bpms[index] < bpms[index - 1]) {
        //                bpmValue = bpmValue - 1
        //            } else if (bpms[index] < bpms[index + 1]) {
        //                bpmValue = bpmValue + 1
        //            }
        //        }
        // BPM201以上の場合はBPMを半分にする
        //        if (bpmValue > 200) {
        //            bpmValue = Int(round(Float(bpmValue) / 2.0)) // round:四捨五入
        //        }
        // print("result bpm:\(bpmValue)")
        return (bpmValue, rv)
    }
    
    fileprivate func getRV(bpms: [Float], bpmMatchMax: Float) -> Float {
        var sum: Float = 0.0
        // マッチ度の平均を求める
        for bpm in 0..<bpms.count {
            let bpmMatchNormal = bpms[bpm] / bpmMatchMax // マッチ度の最大値で割り、マッチ度を最大値1に正規化
            sum += bpmMatchNormal
        }
        let average = sum / Float(bpms.count)
        let rv = (1 - average) * 100
        return rv
        
        // print("Sum: \(sum)")
        // print("Average: \(average)")
        
//        sum = 0.0
//        // マッチ度の標準偏差を求める
//        for bpm in 0..<bpms.count {
//            let bpmMatchNormal = bpms[bpm] / bpmMatchMax // マッチ度の最大値で割り、マッチ度を最大値1に正規化
//            sum += (bpmMatchNormal - average) * (bpmMatchNormal - average)
//        }
//        let dispersion = sum / Float(bpms.count) // 分散
//        // print("Dispersion: \(dispersion)")
//        let sd = sqrt(dispersion) // 標準偏差
//        let rv = (1 - sd) * 100
//        return rv
    }
    
    /* 楽曲情報を解析しBPMとRVを返す */
    func detectSong(url: URL) -> (bpm: Int, rv: Float) {
        print("Prepareing BPM Analyze...")
        var err: OSStatus = noErr
        var theFileLengthInFrames: Int64 = 0
        var theFileFormat: AudioStreamBasicDescription = AudioStreamBasicDescription()
        var thePropertySize: UInt32 = UInt32(MemoryLayout.stride(ofValue: theFileFormat))
        var extAudioFileRef: ExtAudioFileRef? = nil
        var theData: UnsafeMutablePointer<Int16>? = nil
        var theOutputFormat: AudioStreamBasicDescription = AudioStreamBasicDescription()
        var outDataSize: ALsizei
        // var outDataFormat: ALenum
        var outSampleRate: ALsizei
        
        err = ExtAudioFileOpenURL(url as CFURL, &extAudioFileRef)
        if err != 0 { print("MyGetOpenALAudioData: ExtAudioFileOpenURL FAILED, Error = \(err)");  }
        // nilチェック
        guard let extRef = extAudioFileRef else {
            return (-1,1)
        }
        // オーディオデータ形式を取得 (Get the audio data format)
        err = ExtAudioFileGetProperty(extRef, kExtAudioFileProperty_FileDataFormat, &thePropertySize, &theFileFormat)
        if err != 0 { print("MyGetOpenALAudioData: ExtAudioFileGetProperty(kExtAudioFileProperty_FileDataFormat) FAILED, Error = \(err)");}
        if theFileFormat.mChannelsPerFrame > 2 { print("MyGetOpenALAudioData - Unsupported Format, channel count is greater than stereo"); }
        
        // クライアント形式に16ビット符号付き整数を設定
        // (Set the client format to 16 bit signed integer (native-endian) data)
        // 元の楽曲データのチャンネル数及びサンプルレートを維持
        // (Maintain the channel count and sample rate of the original source format)
        theOutputFormat.mSampleRate = theFileFormat.mSampleRate
        theOutputFormat.mChannelsPerFrame = theFileFormat.mChannelsPerFrame
        
        // 変換後の形式にリニアPCM形式に指定
        theOutputFormat.mFormatID = kAudioFormatLinearPCM
        theOutputFormat.mBytesPerPacket = 2 * theOutputFormat.mChannelsPerFrame
        theOutputFormat.mFramesPerPacket = 1
        theOutputFormat.mBytesPerFrame = 2 * theOutputFormat.mChannelsPerFrame
        theOutputFormat.mBitsPerChannel = 16
        theOutputFormat.mFormatFlags = kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger
        
        // 指定した形式へ変換
        print("Converting MusicData to LinearPCM...")
        err = ExtAudioFileSetProperty(extRef, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout.stride(ofValue: theOutputFormat)), &theOutputFormat)
        if err != 0 { print("MyGetOpenALAudioData: ExtAudioFileSetProperty(kExtAudioFileProperty_ClientDataFormat) FAILED, Error = \(err)");}
        
        // 全フレームの取得 (Get the total frame count)
        thePropertySize = UInt32(MemoryLayout.stride(ofValue: theFileLengthInFrames))
        err = ExtAudioFileGetProperty(extRef, kExtAudioFileProperty_FileLengthFrames, &thePropertySize, &theFileLengthInFrames)
        if err != 0 { print("MyGetOpenALAudioData: ExtAudioFileGetProperty(kExtAudioFileProperty_FileLengthFrames) FAILED, Error = \(err)"); }
        
        // メモリ内に全データを読み込む (Read all the data into memory)
        let dataSize = UInt32(theFileLengthInFrames) * theOutputFormat.mBytesPerFrame
        theData = UnsafeMutablePointer.allocate(capacity: Int(dataSize))
        if theData != nil {
            var theDataBuffer: AudioBufferList = AudioBufferList()
            theDataBuffer.mNumberBuffers = 1
            theDataBuffer.mBuffers.mDataByteSize = dataSize
            theDataBuffer.mBuffers.mNumberChannels = theOutputFormat.mChannelsPerFrame
            theDataBuffer.mBuffers.mData = UnsafeMutableRawPointer(theData)
            
            // AudioBufferListにデータを読み込む (Read the data into an AudioBufferList
            var ioNumberFrames: UInt32 = UInt32(theFileLengthInFrames)
            err = ExtAudioFileRead(extRef, &ioNumberFrames, &theDataBuffer)
            if err == noErr {
                outDataSize = ALsizei(dataSize)
                // outDataFormat = (theOutputFormat.mChannelsPerFrame > 1) ? AL_FORMAT_STEREO16 : AL_FORMAT_MONO16
                outSampleRate = ALsizei(theOutputFormat.mSampleRate)
                // ポインタから配列へ格納
                let src: UnsafeMutablePointer<Int16> = UnsafeMutablePointer<Int16>(theData!)
                let soundArray = Array(UnsafeBufferPointer(start: src, count: Int(theFileLengthInFrames)))
                // print("Complete ConvertToLinearPCM")
                // printDebugAudioInfo(dataSize, outSampleRate, arraysize.count) // デバッグ用
                print("Analyzing BPM/RV...")
                // BPM算出に用いるパラメータの準備
                let rate = Int(outSampleRate)
                let frameSize = 512
                let sampleTotal = Int(theFileLengthInFrames)
                let sampleMax = sampleTotal - (sampleTotal % frameSize)
                let frameMax = sampleMax / frameSize
                let diffList = createDiff(soundArray, frameSize, frameMax) // 音量の増加分リストを取得
                // BPM, RVを算出
                let detectedValue = getBestMatchedBpmAndRV(diffList, rate: rate, frameSize: frameSize)
                
                // Match度の保存
                //                let formatter = DateFormatter()
                //                formatter.dateFormat = "yyyyMMdd_HHmmss"
                //                let csvFile = formatter.string(from: Date()) + ".csv"
                //                saveCSV(fileName: csvFile)
                
                MyFreeOpenALAudioData(theData!, outDataSize) // メモリ解放
                print("Complete")
                return (detectedValue.bpm, detectedValue.rv)
            } else {
                // 失敗した場合
                theData?.deallocate(capacity: Int(dataSize))
                theData = nil
                print("MyGetOpenALAudioData: ExtAudioFileRead FAILED, Error = \(err)");
            }
        }
        return (-1,-1)
    }
    
    fileprivate func printDebugAudioInfo(_ dataSize: UInt32, outSampleRate: ALsizei, count: Int ) {
        print("dataSize:\(dataSize)")
        print("outSampleRate:\(outSampleRate)")
        print("arraysize:\(count)")
    }
    
//    func saveCSV(fileName: String) {
//        if let documentDirectoryFileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last {
//            let targetTextFilePath = documentDirectoryFileURL.appendingPathComponent(fileName)
//            saveTextFile(fileURL: targetTextFilePath)
//        }
//    }
//
//    func saveTextFile(fileURL: URL) {
//        do {
//            let stringToWrite = matchData
//            try stringToWrite.write(to: fileURL, atomically: true, encoding: String.Encoding.utf8)
//        } catch let error {
//            print("failed to append: \(error)")
//        }
//    }
    
}

