//
//  ModelPhoneCoolerDevice.swift
//  Swae
//
//  Created by Krister Berntsen on 09/06/2025.
//

import BlackSharkLib
import Foundation

extension Model {
    func enablePhoneCoolerDevice(device: SettingsPhoneCoolerDevice) {
        if !phoneCoolerDevices.keys.contains(device.bluetoothPeripheralId!) {
            let phoneCoolerDevice = PhoneCoolerDevice()
            phoneCoolerDevice.delegate = self
            phoneCoolerDevices[device.bluetoothPeripheralId!] = phoneCoolerDevice
        }
        phoneCoolerDevices[device.bluetoothPeripheralId!]?.start(
            deviceId: device.bluetoothPeripheralId)
    }

    func disablePhoneCoolerDevice(device: SettingsPhoneCoolerDevice) {
        phoneCoolerDevices[device.id]?.stop()
    }
}

extension Model: PhoneCoolerDeviceDelegate {
    func phoneCoolerDeviceState(_: PhoneCoolerDevice, state: PhoneCoolerDeviceState) {
        DispatchQueue.main.async {
            self.statusTopRight.phoneCoolerDeviceState = state
        }
    }

    func phoneCoolerStatus(_: PhoneCoolerDevice, status: BlackSharkLib.CoolingState) {
        DispatchQueue.main.async {
            self.statusTopRight.phoneCoolerPhoneTemp = status.phoneTemperature
            self.statusTopRight.phoneCoolerExhaustTemp = status.heatsinkTemperature
        }
    }

    func autoStartPhoneCoolerDevices() {
        for device in database.phoneCoolerDevices.devices where device.enabled {
            enablePhoneCoolerDevice(device: device)
        }
    }
}
