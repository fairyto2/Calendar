//
//  CalendarController.swift
//  Calendar
//
//  Created by Emil Kreutzman on 08/10/2017.
//  Copyright © 2017 Emil Kreutzman. All rights reserved.
//

import Cocoa

struct Day {
    var isNumber = false
    var isToday = false
    var isCurrentMonth = false
    var isWeekend = false
    var text = "0"
    var lunarDay: String? = nil // 阴历日期
    var holidayDaycode: Int? = nil // 节假日类型代码
}

class CalendarController: NSObject {
    
    var calendar = Calendar.autoupdatingCurrent
    let formatter = DateFormatter()
    let monthFormatter = DateFormatter()
    let dateFormatter = DateFormatter() // 用于格式化日期字符串
    var locale: Locale!
    var timer: Timer? = nil
    
    var shownItemCount = 0
    var weekdays: [String] = []
    var daysInWeek = 0
    var monthOffset = 0
    
    var currentMonth: Date? = nil
    var lastFirstWeekdayLastMonth: Date? = nil
    var lastTick: Date? = Date()
    var tick: Date? = nil
    var tickInterval: Double = 60
    
    var onTimeUpdate: (() -> ())? = nil
    var onCalendarUpdate: (() -> ())? = nil
    
    // 存储节假日信息，key为日期字符串(yyyy-MM-dd)，value为HolidayInfo
    private var holidayInfo: [String: HolidayInfo] = [:]
    private var holidayAPI: HolidayAPI? = nil
    // 错误处理闭包
    var onAPIError: ((String) -> Void)? = nil
    
    override init() {
        super.init()
        
        let languageIdentifier = Locale.preferredLanguages[0]
        locale = Locale.init(identifier: languageIdentifier)
        
        monthFormatter.locale = locale
        monthFormatter.dateFormat = "MMMM yyyy"
        
        // 设置日期格式化器
        dateFormatter.locale = locale
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        calendar.locale = locale
        weekdays = calendar.veryShortWeekdaySymbols
        daysInWeek = weekdays.count
        
        let maxWeeksInMonth = (calendar.maximumRange(of: .day)?.upperBound)! / daysInWeek
        shownItemCount = daysInWeek * (maxWeeksInMonth + 2 + 1)
        
        // 初始化节假日API
        holidayAPI = HolidayAPI()
        
        updateCurrentlyShownDays()
    }
    
    func setDateFormat() {
        let defaults = UserDefaults.standard
        let keys = SettingsKeys()
        
        let showSeconds = defaults.bool(forKey: keys.SHOW_SECONDS_KEY)
        let use24Hours = defaults.bool(forKey: keys.USE_HOURS_24_KEY)
        let showAMPM = defaults.bool(forKey: keys.SHOW_AM_PM_KEY)
        let showDate = defaults.bool(forKey: keys.SHOW_DATE_KEY)
        let showDayOfWeek = defaults.bool(forKey: keys.SHOW_DAY_OF_WEEK_KEY)
        let showAnyDateInfo = showDayOfWeek || showDate
        
        formatter.locale = locale
        
        var dateTemplate = ""
        dateTemplate += (showDayOfWeek) ? "EEE" : ""
        dateTemplate += (showDate) ? "dMMM" : ""
        
        formatter.setLocalizedDateFormatFromTemplate(dateTemplate)
        let dateFormat = (showAnyDateInfo) ? formatter.dateFormat!.replacingOccurrences(of: ",", with: "") + "  " : ""
        
        var timeTemplate = "mm"
        timeTemplate += (showSeconds) ? "ss" : ""
        timeTemplate += (use24Hours) ? "H" : "h"
        
        formatter.setLocalizedDateFormatFromTemplate(timeTemplate)
        var timeFormat = formatter.dateFormat!
        
        if (use24Hours || !showAMPM) {
            timeFormat = timeFormat.replacingOccurrences(of: "a", with: "")
        }
        
        formatter.dateFormat = String(format: "%@%@", dateFormat, timeFormat)
        initTiming(useSeconds: showSeconds)
    }
    
    private func onTick(timer: Timer) {
        tick = calendar.date(byAdding: .second, value: Int(tickInterval), to: lastTick!)
        
        onTimeUpdate?()
        if (!calendar.isDate(tick!, equalTo: lastTick!, toGranularity: .day)) {
            onCalendarUpdate?()
        }
        
        let now = Date()
        let timeDeviation = abs((tick?.timeIntervalSince1970)! - now.timeIntervalSince1970)
        
        // allow maximum time deviation of 0.5 seconds
        if (timeDeviation > 0.5) {
            tick = now
        }
        
        lastTick = tick
    }
    
    private func initTiming(useSeconds: Bool) {
        tickInterval = (useSeconds) ? 1 : 60
        let now = Date()
        let fireAfter = (useSeconds) ? 1 : 60 - calendar.component(.second, from: now)
        
        // kill any previous timers
        timer?.invalidate()
        
        let fireAt = calendar.date(byAdding: .second, value: fireAfter, to: now)!
        timer = Timer(fire: fireAt, interval: tickInterval, repeats: true, block: onTick)
        RunLoop.main.add(timer!, forMode: RunLoopMode.commonModes)
        
        // tick once to update straight away
        lastTick = calendar.date(byAdding: .second, value: Int(-tickInterval), to: now)
        onTick(timer: timer!)
    }
    
    private func daysInMonth(month: Date) -> Int {
        return (calendar.range(of: .day, in: .month, for: month)?.count)!
    }
    
    private func getLastFirstWeekday(month: Date) -> Date {
        // zero-based weekday of the date "month"
        let weekday = (daysInWeek + calendar.component(.weekday, from: month) - calendar.firstWeekday) % daysInWeek
        
        // the date of the first day that same week (eg. the monday of that week)
        let d = calendar.ordinality(of: .day, in: .month, for: month)! - weekday
        
        // calculate full weeks left after the day number "d" and add that to d, to get the "last first day of the month"
        let totalDaysInMonth = daysInMonth(month: month)
        let lastFirstWeekdayNumber = (totalDaysInMonth - d) / daysInWeek * daysInWeek + d
        let dayOfMonth = calendar.ordinality(of: .day, in: .month, for: month)!

        return calendar.date(byAdding: .day, value: (lastFirstWeekdayNumber - dayOfMonth), to: month)!
    }
    
    private func updateCurrentlyShownDays() {
        currentMonth = calendar.date(byAdding: .month, value: Int(monthOffset), to: Date())!
        let lastMonth = calendar.date(byAdding: .month, value: Int(-1), to: currentMonth!)!
        lastFirstWeekdayLastMonth = getLastFirstWeekday(month: lastMonth)
        
        // 获取节假日数据，日历会显示前一个月和后一个月的部分日期，在节假日跨月的情况下，只获取当月节假日数据是不行的
        let nextMonth = calendar.date(byAdding: .month, value: Int(+1), to: currentMonth!)!
        fetchHolidayData(forMonth: lastMonth)
        fetchHolidayData(forMonth: currentMonth!)
        fetchHolidayData(forMonth: nextMonth)
    }
    
    private func fetchHolidayData(forMonth month: Date) {
        // 清空之前的节假日数据
        holidayInfo.removeAll()
        
        guard let holidayAPI = holidayAPI else {
            return
        }
        
        holidayAPI.fetchHolidays(forMonth: month) { [weak self] (holidays, error) in
            if let error = error {
                let errorMessage = "API错误: \(error.localizedDescription)"
                print(errorMessage)
                // 传递错误信息到MainMenuController
                DispatchQueue.main.async {
                    self?.onAPIError?(errorMessage)
                }
                return
            }
            
            guard let holidays = holidays else {
                print("未获取到节假日数据")
                return
            }
            
            // 存储节假日数据
            for holiday in holidays {
                self?.holidayInfo[holiday.date] = holiday
            }
            
            // 更新日历显示
            DispatchQueue.main.async {
                self?.onCalendarUpdate?()
            }
        }
    }
    
    func subscribe(onTimeUpdate: @escaping () -> (), onCalendarUpdate: @escaping () -> ()) {
        self.onTimeUpdate = onTimeUpdate
        self.onCalendarUpdate = onCalendarUpdate
        
        if (tick == nil) {
            onCalendarUpdate()
            setDateFormat()
        }
    }
    
    func pause() {
        timer?.invalidate()
        tick = nil
    }
    
    func itemCount() -> Int {
        return shownItemCount
    }
    
    func getItemAt(index: Int) -> Day {
        var day = Day()
        
        if (index < daysInWeek) {
            day.text = weekdays[(calendar.firstWeekday + index - 1) % daysInWeek]
        } else {
            let dayOffset = index - daysInWeek
            guard let lastFirstWeekday = lastFirstWeekdayLastMonth else { return Day() }
            let date = calendar.date(byAdding: .day, value: dayOffset, to: lastFirstWeekday)!
            
            day.isNumber = true
            day.text = String(calendar.ordinality(of: .day, in: .month, for: date)!)
            day.isCurrentMonth = calendar.isDate(date, equalTo: currentMonth!, toGranularity: .month)
            day.isToday = calendar.isDateInToday(date)
            
            // 设置节假日信息、阴历日期
            let dateString = dateFormatter.string(from: date)
            if let holidayData = holidayInfo[dateString] {
                day.holidayDaycode = holidayData.daycode
                day.lunarDay = holidayData.lunarday == "初一" ? holidayData.lunarmonth : holidayData.lunarday
            } else {
                // 处理没有找到对应节日信息的情况
                day.holidayDaycode = nil
                day.lunarDay = "nil"
            }
            
            // 判断是否是周末
            let weekday = calendar.component(.weekday, from: date)
            day.isWeekend = (weekday == 1 || weekday == 7) // 1是周日，7是周六
        }
        
        return day
    }
    
    func getFormattedDate() -> String {
        // notice the added spaces around the date itself
        // they're used as a hack to stop the date from wobbling around in the menu item
        // basically, we're forcing an overflow here
        return formatter.string(from: tick!)
    }
    
    func getMonth() -> String {
        return monthFormatter.string(from: currentMonth!)
    }
    
    func incrementMonth() {
        monthOffset += 1
        updateCurrentlyShownDays()
        onCalendarUpdate?()
    }
    
    func decrementMonth() {
        monthOffset -= 1
        updateCurrentlyShownDays()
        onCalendarUpdate?()
    }
    
    func resetMonth() {
        monthOffset = 0
        updateCurrentlyShownDays()
        onCalendarUpdate?()
    }
    
    // 重新获取节假日数据
    func refreshHolidayData() {
        // 清空之前的节假日数据
        holidayInfo.removeAll()
        
        // 重新获取当前显示的三个月的节假日数据
        if let currentMonth = currentMonth {
            let lastMonth = calendar.date(byAdding: .month, value: Int(-1), to: currentMonth)!
            let nextMonth = calendar.date(byAdding: .month, value: Int(+1), to: currentMonth)!
            fetchHolidayData(forMonth: lastMonth)
            fetchHolidayData(forMonth: currentMonth)
            fetchHolidayData(forMonth: nextMonth)
        }
    }
}
