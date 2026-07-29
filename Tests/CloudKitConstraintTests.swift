import Testing
import SwiftData
@testable import WiseWalk

/// design-spec §4.6：SwiftData + CloudKit 的四条硬约束。
/// 违反其中任何一条，同步会在真机上静默失效或直接崩溃，
/// 而模拟器上的本地存储照跑不误——所以必须在这里拦住。

@Test func 没有任何实体使用唯一约束() {
    for entity in ModelContainerFactory.syncedSchema.entities {
        #expect(
            entity.uniquenessConstraints.isEmpty,
            "\(entity.name) 使用了 @Attribute(.unique)，CloudKit 不支持"
        )
    }
}

@Test func 所有属性要么可选要么有默认值() {
    for entity in ModelContainerFactory.syncedSchema.entities {
        for attr in entity.attributes where !attr.isTransient {
            #expect(
                attr.isOptional || attr.defaultValue != nil,
                "\(entity.name).\(attr.name) 既非可选也无默认值，CloudKit 无法同步"
            )
        }
    }
}

@Test func 所有关系均可选() {
    for entity in ModelContainerFactory.syncedSchema.entities {
        for rel in entity.relationships {
            #expect(
                rel.isOptional,
                "\(entity.name).\(rel.name) 关系不可选，CloudKit 要求关系必须可选"
            )
        }
    }
}

@Test func 所有关系都有反向关系() {
    for entity in ModelContainerFactory.syncedSchema.entities {
        for rel in entity.relationships {
            #expect(
                rel.inverseName != nil,
                "\(entity.name).\(rel.name) 缺少反向关系，CloudKit 要求关系必须成对"
            )
        }
    }
}

@Test func 模型清单完整() {
    let names = Set(ModelContainerFactory.syncedSchema.entities.map(\.name))
    #expect(names == ["PracticeItem", "PracticeSession", "DaySnapshot"])
}

@Test func 建模属性必须逐一登记在白名单() {
    // design-spec §4.4：今日总数缓存**绝对不能**进 CloudKit，
    // 否则又变回「存总数」的老路，整记录级 LWW 下多设备必然互相覆盖。
    // 缓存的正确去处是 App Group UserDefaults（第 4 卷），永不进 CloudKit。
    //
    // 黑名单只拦住四种拼写，runningTotal / dailySum / sum / count 都能蒙混过关。
    // 改用白名单：任何新增的建模属性都会让本测试变红，逼迫开发者停下来确认——
    // 这不是缓存/聚合量吗？确认无误后，再把它加进下面对应实体的白名单。
    //
    // 注意：source / measureType / scheduleRule 等是计算门面，不落库，不会出现在 attributes。
    let allowed: [String: Set<String>] = [
        "PracticeSession": [
            "id", "dayKey", "tzOffsetMinutes", "amount", "startedAt", "endedAt",
            "sourceRaw", "deviceName", "note", "createdAt"
        ],
        "DaySnapshot": [
            "id", "dayKey", "requiredItemIDs", "goals", "createdAt"
        ],
        "PracticeItem": [
            "id", "name", "iconName", "colorHex", "measureTypeRaw", "unit", "dailyGoal",
            "scheduleRuleRaw", "reminderTimes", "sortOrder", "isArchived", "templateKey",
            "createdAt", "updatedAt"
        ]
    ]
    for entity in ModelContainerFactory.syncedSchema.entities {
        guard let whitelist = allowed[entity.name] else {
            Issue.record("\(entity.name) 未登记白名单，新实体的每个建模属性都需先确认再登记")
            continue
        }
        for attr in entity.attributes {
            #expect(
                whitelist.contains(attr.name),
                "\(entity.name).\(attr.name) 不在白名单中。若确认它既非今日总数缓存也非可变聚合量，再把它加入本测试对应实体的白名单；缓存/聚合量属于 App Group UserDefaults，不可进 CloudKit。"
            )
        }
    }
}

@Test func 只有同步schema受CloudKit约束管辖() {
    // 本地库不同步，四条约束对它不适用——但**必须确认它真的不在同步 schema 里**。
    // 这条与 SessionDraftTests.草稿绝不在同步schema里 是同一件事的两面：
    // 那边从草稿的角度看，这边从约束守卫的角度看，防的是有人只改一处就以为过关了。
    let syncedNames = Set(ModelContainerFactory.syncedSchema.entities.map(\.name))
    for entity in ModelContainerFactory.localSchema.entities {
        #expect(!syncedNames.contains(entity.name),
                "\(entity.name) 同时出现在两套 schema 里。本地实体一旦进了同步 schema，就会被传到别的设备上")
    }
}
