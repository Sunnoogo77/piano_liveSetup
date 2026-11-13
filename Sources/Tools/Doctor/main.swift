import AVFoundation
import CoreAudio
import CoreMIDI
import Foundation

// Que voit le Mac, au juste ?
//
// Un instrument branché qui n'apparaît nulle part, c'est trois questions dans
// l'ordre : le Mac le voit-il sur le bus USB ? expose-t-il une interface MIDI
// normalisée ? et le port est-il celui qui parle à l'ordinateur ? Cet outil y
// répond sans jouer une note et sans rien modifier.
//
//     make doctor

// MARK: - MIDI

func midiName(_ o: MIDIObjectRef) -> String {
    var s: Unmanaged<CFString>?
    MIDIObjectGetStringProperty(o, kMIDIPropertyDisplayName, &s)
    return (s?.takeRetainedValue() as String?) ?? "?"
}

func midiDeviceOf(_ endpoint: MIDIEndpointRef) -> MIDIDeviceRef? {
    var entity = MIDIEntityRef()
    guard MIDIEndpointGetEntity(endpoint, &entity) == noErr, entity != 0 else { return nil }
    var device = MIDIDeviceRef()
    guard MIDIEntityGetDevice(entity, &device) == noErr, device != 0 else { return nil }
    return device
}

// MARK: - Audio

func audioName(_ id: AudioObjectID) -> String {
    var a = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                       mScope: kAudioObjectPropertyScopeGlobal,
                                       mElement: kAudioObjectPropertyElementMain)
    var nm: Unmanaged<CFString>?
    var sz = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id, &a, 0, nil, &sz, &nm) == noErr, let nm else { return "?" }
    return nm.takeRetainedValue() as String
}

func outChannels(_ id: AudioObjectID) -> Int {
    var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                       mScope: kAudioObjectPropertyScopeOutput,
                                       mElement: kAudioObjectPropertyElementMain)
    var sz: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &sz) == noErr, sz > 0 else { return 0 }
    let buf = UnsafeMutableRawPointer.allocate(byteCount: Int(sz), alignment: 8)
    defer { buf.deallocate() }
    guard AudioObjectGetPropertyData(id, &a, 0, nil, &sz, buf) == noErr else { return 0 }
    return UnsafeMutableAudioBufferListPointer(buf.assumingMemoryBound(to: AudioBufferList.self))
        .reduce(0) { $0 + Int($1.mNumberChannels) }
}

func bufferRange(_ id: AudioObjectID) -> String {
    var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyBufferFrameSizeRange,
                                       mScope: kAudioObjectPropertyScopeGlobal,
                                       mElement: kAudioObjectPropertyElementMain)
    var r = AudioValueRange()
    var sz = UInt32(MemoryLayout<AudioValueRange>.size)
    guard AudioObjectGetPropertyData(id, &a, 0, nil, &sz, &r) == noErr else { return "?" }
    return "\(Int(r.mMinimum))–\(Int(r.mMaximum))"
}

func isPrivateAggregate(_ id: AudioObjectID) -> Bool {
    var a = AudioObjectPropertyAddress(mSelector: kAudioAggregateDevicePropertyComposition,
                                       mScope: kAudioObjectPropertyScopeGlobal,
                                       mElement: kAudioObjectPropertyElementMain)
    var dict: Unmanaged<CFDictionary>?
    var sz = UInt32(MemoryLayout<Unmanaged<CFDictionary>?>.size)
    guard AudioObjectGetPropertyData(id, &a, 0, nil, &sz, &dict) == noErr,
          let d = dict?.takeRetainedValue() as? [String: Any] else { return false }
    return ((d["private"] as? NSNumber)?.intValue ?? 0) != 0
}

func audioDevices() -> [AudioObjectID] {
    var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                       mScope: kAudioObjectPropertyScopeGlobal,
                                       mElement: kAudioObjectPropertyElementMain)
    var sz: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &sz)
    var ids = [AudioObjectID](repeating: 0, count: Int(sz) / MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &sz, &ids)
    return ids
}

// MARK: - Rapport

func title(_ s: String) {
    print("\n── \(s) " + String(repeating: "─", count: max(0, 54 - s.count)))
}

print("Piano Live Setup — que voit le Mac ?")

title("Ports MIDI")
let sourceCount = MIDIGetNumberOfSources()
let destCount = MIDIGetNumberOfDestinations()
if sourceCount == 0 {
    print("  aucune source : aucun instrument ne parle au Mac")
} else {
    for i in 0..<sourceCount {
        let src = MIDIGetSource(i)
        let dev = midiDeviceOf(src)
        let back = (0..<destCount)
            .map { MIDIGetDestination($0) }
            .first { midiDeviceOf($0) == dev }
        print("  reçoit de « \(midiName(src)) »")
        print("    retour possible vers : \(back.map { "« \(midiName($0)) »" } ?? "aucun — le son interne ne pourra pas être coupé")")
    }
}
let sourceDevices = Set((0..<sourceCount).compactMap { midiDeviceOf(MIDIGetSource($0)) })
for i in 0..<destCount {
    let d = MIDIGetDestination(i)
    guard let dev = midiDeviceOf(d), !sourceDevices.contains(dev) else { continue }
    print("  peut parler à « \(midiName(d)) », qui ne renvoie rien")
}

title("Appareils USB")
let usb = USBScan.devices()
if usb.isEmpty {
    print("  rien sur le bus USB")
}
for d in usb {
    let classes = Set(d.interfaceClasses).sorted().map(String.init).joined(separator: ", ")
    print("  \(d.name)  —  \(d.vendor)")
    print("    interfaces de classe : \(classes.isEmpty ? "aucune lue" : classes)")
    if d.hasStandardMIDI {
        print("    MIDI normalisé : oui — macOS le lit sans rien installer")
    } else if d.looksProprietary {
        print("    MIDI normalisé : NON, interfaces propriétaires (classe 255).")
        print("    → cet instrument demande le pilote USB de son fabricant, ou")
        print("      bien branchez sa prise MIDI DIN sur un boîtier USB-MIDI.")
    }
}

title("Sorties audio")
for id in audioDevices() where outChannels(id) > 0 {
    let privateMark = isPrivateAggregate(id) ? "   (agrégat privé de macOS — écarté par l'application)" : ""
    print("  \(audioName(id))  —  \(outChannels(id)) canal(aux), tampon \(bufferRange(id))\(privateMark)")
}

title("Entrées audio")
for id in audioDevices() where outChannels(id) == 0 {
    print("  \(audioName(id))")
}

print("")
