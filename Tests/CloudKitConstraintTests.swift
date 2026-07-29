import Testing
import SwiftData
@testable import WiseWalk

/// design-spec §4.6：SwiftData + CloudKit 的四条硬约束。
/// 违反其中任何一条，同步会在真机上静默失效或直接崩溃，
/// 而模拟器上的本地存储照跑不误——所以必须在这里拦住。

@Test func 没有任何实体使用唯一约束() {
    for entity in ModelContainerFactory.schema.entities {
        #expect(
            entity.uniquenessConstraints.isEmpty,
            "\(entity.name) 使用了 @Attribute(.unique)，CloudKit 不支持"
        )
    }
}

@Test func 所有属性要么可选要么有默认值() {
    for entity in ModelContainerFactory.schema.entities {
        for attr in entity.attributes where !attr.isTransient {
            #expect(
                attr.isOptional || attr.defaultValue != nil,
                "\(entity.name).\(attr.name) 既非可选也无默认值，CloudKit 无法同步"
            )
        }
    }
}

@Test func 所有关系均可选() {
    for entity in ModelContainerFactory.schema.entities {
        for rel in entity.relationships {
            #expect(
                rel.isOptional,
                "\(entity.name).\(rel.name) 关系不可选，CloudKit 要求关系必须可选"
            )
        }
    }
}

@Test func 所有关系都有反向关系() {
    for entity in ModelContainerFactory.schema.entities {
        for rel in entity.relationships {
            #expect(
                rel.inverseName != nil,
                "\(entity.name).\(rel.name) 缺少反向关系，CloudKit 要求关系必须成对"
            )
        }
    }
}

@Test func 模型清单完整() {
    let names = Set(ModelContainerFactory.schema.entities.map(\.name))
    #expect(names == ["PracticeItem", "PracticeSession", "DaySnapshot"])
}

@Test func 今日总数不得成为建模属性() {
    // design-spec §4.4：今日总数缓存**绝对不能**进 CloudKit，
    // 否则又变回「存总数」的老路，多设备必然互相覆盖。
    // 缓存的正确去处是 App Group UserDefaults（第 4 卷）。
    let forbidden = ["todayTotal", "cachedTotal", "total", "todayCount"]
    for entity in ModelContainerFactory.schema.entities {
        for attr in entity.attributes {
            #expect(
                !forbidden.contains(attr.name),
                "\(entity.name).\(attr.name) 是缓存字段，不可建模持久化"
            )
        }
    }
}
