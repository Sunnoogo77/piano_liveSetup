import Foundation
import IOKit
import IOKit.usb

/// Ce que le Mac voit sur le bus USB, et surtout : l'appareil parle-t-il la
/// langue que macOS comprend sans rien installer ?
///
/// Un instrument branché qui n'apparaît pas en MIDI n'est pas forcément mal
/// branché. Certains — surtout des synthétiseurs de studio — n'exposent que des
/// interfaces propriétaires et demandent le pilote de leur fabricant. Sans cette
/// lecture, l'application ne peut dire que « aucun clavier détecté », ce qui
/// envoie l'utilisateur chercher un câble qui n'est pas en cause.
struct USBDevice: Equatable {
    let name: String
    let vendor: String
    /// Classes d'interface USB exposées par l'appareil.
    let interfaceClasses: [Int]
    /// Vrai quand l'appareil expose une interface audio de sous-classe 3,
    /// « MIDI Streaming » : c'est elle que macOS lit sans aucun pilote.
    let hasStandardMIDI: Bool
    /// Vrai quand l'appareil expose une interface audio de sous-classe 2,
    /// « Audio Streaming » : il sait alors recevoir ou émettre du son par USB.
    let hasUSBAudio: Bool

    /// Un appareil qui expose du propriétaire (classe 255) sans interface MIDI
    /// normalisée : la signature d'un instrument qui réclame le pilote de son
    /// fabricant.
    ///
    /// On n'exige pas que *toutes* ses interfaces soient propriétaires : un
    /// Yamaha MOXF en expose aussi une de classe 3 (HID), et le filtre strict
    /// l'écartait — lui précisément, l'instrument pour lequel ce test existe.
    /// On écarte en revanche ce qui ne peut pas être un instrument.
    var looksProprietary: Bool {
        guard !hasStandardMIDI, interfaceClasses.contains(255) else { return false }
        // Réseau, imprimante, clé, concentrateur, webcam, sans-fil : pas un piano.
        let notAnInstrument: Set<Int> = [2, 6, 7, 8, 9, 10, 14, 224]
        return !interfaceClasses.contains { notAnInstrument.contains($0) }
    }
}

enum USBScan {

    /// Tous les appareils du bus, hubs et périphériques du Mac compris.
    static func devices() -> [USBDevice] {
        var found: [USBDevice] = []
        guard let match = IOServiceMatching(kIOUSBDeviceClassName) else { return [] }
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }

        while case let device = IOIteratorNext(iterator), device != 0 {
            defer { IOObjectRelease(device) }
            guard let name = string(device, "USB Product Name") else { continue }

            var classes: [Int] = []
            var midi = false
            var audio = false
            // Les interfaces sont les enfants du nœud de l'appareil.
            var children = io_iterator_t()
            if IORegistryEntryGetChildIterator(device, kIOServicePlane, &children) == KERN_SUCCESS {
                defer { IOObjectRelease(children) }
                while case let child = IOIteratorNext(children), child != 0 {
                    defer { IOObjectRelease(child) }
                    guard let cls = number(child, "bInterfaceClass") else { continue }
                    classes.append(cls)
                    guard cls == 1, let sub = number(child, "bInterfaceSubClass") else { continue }
                    if sub == 3 { midi = true }
                    if sub == 2 { audio = true }
                }
            }
            found.append(USBDevice(name: name,
                                   vendor: string(device, "USB Vendor Name") ?? "—",
                                   interfaceClasses: classes,
                                   hasStandardMIDI: midi,
                                   hasUSBAudio: audio))
        }
        return found.sorted { $0.name < $1.name }
    }

    /// Les appareils qui ressemblent à un instrument réclamant un pilote.
    /// On ne devine pas la marque : on lit ce que l'appareil déclare.
    static func proprietaryInstruments() -> [USBDevice] {
        devices().filter { $0.looksProprietary }
    }

    private static func string(_ obj: io_object_t, _ key: String) -> String? {
        guard let v = IORegistryEntryCreateCFProperty(obj, key as CFString, kCFAllocatorDefault, 0)
        else { return nil }
        return v.takeRetainedValue() as? String
    }

    private static func number(_ obj: io_object_t, _ key: String) -> Int? {
        guard let v = IORegistryEntryCreateCFProperty(obj, key as CFString, kCFAllocatorDefault, 0)
        else { return nil }
        return (v.takeRetainedValue() as? NSNumber)?.intValue
    }
}
