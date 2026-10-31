import Foundation
let dir = AppPaths.sounds.path
let target = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let filter = CommandLine.arguments.count > 2 ? CommandLine.arguments[2].lowercased() : ""
guard let settings = new_fluid_settings(), let synth = new_fluid_synth(settings) else { exit(1) }
let id = fluid_synth_sfload(synth, dir + "/" + target, 0)
guard id != FLUID_FAILED, let sf = fluid_synth_get_sfont_by_id(synth, id) else { print("échec"); exit(1) }
fluid_sfont_iteration_start(sf)
while let pre = fluid_sfont_iteration_next(sf) {
    let nm = String(cString: fluid_preset_get_name(pre))
    let line = String(format: "%3d/%-3d  %@", fluid_preset_get_banknum(pre), fluid_preset_get_num(pre), nm)
    if filter.isEmpty || nm.lowercased().contains(filter) { print(line) }
}
