import SwiftUI

/// Appearance shared by pie, timeline, radar, XY, Gantt and Kanban diagrams.
/// Empty palettes/maps and nil overrides inherit each diagram's existing appearance.
/// Dimensions use unscaled diagram points. This configures painting, not the layout algorithm.
public struct MarkdownMermaidChartTokens {
    public var seriesColors: [Color] = []
    public var ganttStatusColors: [MermaidGanttStatus: Color] = [:]
    public var kanbanPriorityColors: [MermaidKanbanPriority: Color] = [:]
    public var todayColor: Color?
    public var overLimitColor: Color?
    public var atLimitColor: Color?
    public var belowLimitColor: Color?
    public var gridColor: Color?
    public var columnBackground: Color?
    public var cardBackground: Color?
    public var sectorBorderColor: Color?
    public var sectorBorderWidth: CGFloat?
    public var seriesLineWidth: CGFloat?
    public var pointRadius: CGFloat?
    public var fillOpacity: Double?
    public var barCornerRadius: CGFloat = 3
    public var taskCornerRadius: CGFloat = 4
    public var columnCornerRadius: CGFloat = 8
    public var cardCornerRadius: CGFloat = 6
    public var borderWidth: CGFloat = 1
    public var gridWidth: CGFloat = 1
    public var priorityStripeWidth: CGFloat = 4
    public var todayLineWidth: CGFloat = 2

    public init() {}

    /// Safe copy for both standalone and fenced renderers; the input is never mutated.
    public func normalized() -> Self {
        var value = self
        value.sectorBorderWidth = sectorBorderWidth.map(MarkdownTokenValidation.dimension)
        value.seriesLineWidth = seriesLineWidth.map(MarkdownTokenValidation.dimension)
        value.pointRadius = pointRadius.map(MarkdownTokenValidation.dimension)
        value.fillOpacity = fillOpacity.map(MarkdownTokenValidation.opacity)
        value.barCornerRadius = MarkdownTokenValidation.dimension(barCornerRadius)
        value.taskCornerRadius = MarkdownTokenValidation.dimension(taskCornerRadius)
        value.columnCornerRadius = MarkdownTokenValidation.dimension(columnCornerRadius)
        value.cardCornerRadius = MarkdownTokenValidation.dimension(cardCornerRadius)
        value.borderWidth = MarkdownTokenValidation.dimension(borderWidth)
        value.gridWidth = MarkdownTokenValidation.dimension(gridWidth)
        value.priorityStripeWidth = MarkdownTokenValidation.dimension(priorityStripeWidth)
        value.todayLineWidth = MarkdownTokenValidation.dimension(todayLineWidth)
        return value
    }

    func seriesColor(_ index: Int, fallback: Color) -> Color {
        seriesColors.isEmpty ? fallback : seriesColors[max(0, index) % seriesColors.count]
    }
}
