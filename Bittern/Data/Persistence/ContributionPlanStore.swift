//
//  ContributionPlanStore.swift
//  Bittern
//

import Foundation

extension ContributionPlan {
    static func load(from defaults: UserDefaults = .standard) -> ContributionPlan {
        guard let data = defaults.data(forKey: AppSettingKey.contributionPlan),
              let plan = try? JSONDecoder().decode(ContributionPlan.self, from: data)
        else {
            return .empty
        }
        return plan
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: AppSettingKey.contributionPlan)
    }
}
