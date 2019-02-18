//
//  ViewController.swift
//  BPMRVDetector
//
//  Created by Atsushi Otsubo on 2017/09/29.
//  Copyright © 2017年 Rirex. All rights reserved.
//

import UIKit
import MediaPlayer

class ViewController: UIViewController, MPMediaPickerControllerDelegate {
    
    @IBOutlet weak var songNameLabel: UILabel!
    @IBOutlet weak var bpmLabel: UILabel!
    @IBOutlet weak var rvLabel: UILabel!
    @IBOutlet weak var progressLabel: UILabel!
    
    let csvService = CSVService()
    var csvData = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        initialize()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func initialize() {
        csvData = "Id, Name, Artist, Album, Genre, Time, BPM, RV"
        let query = MPMediaQuery.songs()
        
        let items = query.items!
        // 非同期処理内の一部のみ同期処理にする
        DispatchQueue.global(qos: .default).async {
            
            for i in 0..<items.count {
                
                if (700 <= i && i < items.count) {
                    let item = items[i]
                    if let url: URL = item.assetURL {
                        print("Title: \(item.title ?? "item")")
                        
                        let result = self.bpmDetector(url: url)
                        
                        let data = "\n\(i),\(item.title ?? ""),\(item.artist ?? ""),\(item.albumTitle ?? ""),\(item.genre ?? ""),\(item.playbackDuration),\(result.bpm),\(result.rv)"
                        self.csvData += data
                        print(data)
                        DispatchQueue.main.async {
                            self.songNameLabel.text = item.title
                            self.bpmLabel.text = "BPM: \(result.bpm)"
                            self.rvLabel.text = "RythmicValue: \(result.rv)"
                            self.progressLabel.text = "Progress: " + String(i)
                        }
                    }
                }
            }
            self.csvService.saveCSV(dataStr: self.csvData)
            DispatchQueue.main.async {
                self.progressLabel.text = "Progress: Complete!"
            }
        }
    }
    
    /**
     * 楽曲を選択
     * 楽曲のBPM, RV(Rhythmic Value)を取得
     */
    @IBAction func selectSongButton(_ sender: Any) {
        openMediaPicker()
    }
    
    func openMediaPicker() {
        let picker = MPMediaPickerController()
        picker.delegate = self
        picker.allowsPickingMultipleItems = false
        present(picker, animated: true, completion: nil)
    }
    
    func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems mediaItemCollection: MPMediaItemCollection) {
        // このfunctionを抜ける際にピッカーを閉じ、破棄する
        // (defer文はfunctionを抜ける際に実行される)
        defer {
            dismiss(animated: true, completion: nil)
        }
        
        // 選択した曲情報がmediaItemCollectionに入っている
        // mediaItemCollection.itemsから入っているMPMediaItemの配列を取得できる
        let items = mediaItemCollection.items
        if items.isEmpty {
            return // itemが一つもなかったので戻る
        }
        
        let item = items[0] // 先頭のMPMediaItemを取得し、そのassetURLからプレイヤーを作成する
        if let url: URL = item.assetURL {
            let result = bpmDetector(url: url)
            songNameLabel.text = item.title
            bpmLabel.text = "BPM: \(result.bpm)"
            rvLabel.text = "RythmicValue: \(result.rv)"
        }
        dismiss(animated: true, completion: nil) // ピッカーの破棄
    }
    
    func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
        dismiss(animated: true, completion: nil) // ピッカーの破棄
    }
    
    func bpmDetector(url: URL) -> (bpm: Int,rv: Float) {
        let bpmDetector = BpmDetectService()
        let detectedValue = bpmDetector.detectSong(url: url)
        
        return (detectedValue.bpm, detectedValue.rv)
    }
    
}

