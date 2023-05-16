targetScope = 'resourceGroup'

@description('Deployment region name. Default is the location of the resource group.')
param location string = resourceGroup().location

@description('Deployment tags. Default is empty map.')
param tags object = {}

@description('Required. The administrator username of the server. Can only be specified when the server is being created.')
param administratorLogin string

@secure()
@description('Required. The administrator password of the server. Can only be specified when the server is being created.')
param administratorLoginPassword string

@description('Optional. The number of days a backup is retained.')
@minValue(7)
@maxValue(35)
param backupRetentionDays int = 35

@description('Optional. The mode to create a new server.')
@allowed(['Default', 'GeoRestore', 'PointInTimeRestore', 'Replica'])
param createMode string = 'Default'

@description('Optional. List of databases to create on server.')
param databases array = []

@description('Optional. List of server configurations to create on server.')
param serverConfigurations array = []

@description('Optional. Status showing whether the server enabled infrastructure encryption..')
@allowed(['Enabled', 'Disabled'])
param infrastructureEncryption string = 'Disabled'

type firewallRulesType = {
  @minLength(1)
  @maxLength(128)
  @description('The resource name.')
  name: string
  @description('The start IP address of the server firewall rule. Must be IPv4 format.')
  startIpAddress: string
  @description('The end IP address of the server firewall rule. Must be IPv4 format.')
  endIpAddress: string
}[]

@description('Optional. List of firewall rules to create on server.')
param firewallRules firewallRulesType = []

type virtualNetworkRuleType = {
  @minLength(1)
  @maxLength(128)
  @description('The resource name.')
  name: string
  @description('Create firewall rule before the virtual network has vnet service endpoint enabled.')
  ignoreMissingVnetServiceEndpoint: bool
  @description('The ARM resource id of the virtual network subnet.')
  virtualNetworkSubnetId: string
}

@description('Optional. List of virtualNetworkRules to create on mysql server.')
param virtualNetworkRules virtualNetworkRuleType[] = []

@description('Optional. List of privateEndpoints to create on mysql server.')
param privateEndpoints array = []

@description('Optional. Enable or disable geo-redundant backups.')
@allowed(['Enabled','Disabled'])
param geoRedundantBackup string = 'Enabled'

@description('Optional. Enforce a minimal Tls version for the server.')
@allowed(['TLS1_0', 'TLS1_1', 'TLS1_2', 'TLSEnforcementDisabled'])
param minimalTlsVersion string = 'TLS1_2'

var sslEnforcement = (minimalTlsVersion == 'TLSEnforcementDisabled') ? 'Disabled' : 'Enabled'

@description('Optional. Restore point creation time (ISO8601 format), specifying the time to restore from.')
param restorePointInTime string = ''

@description('Optional. Whether or not public network access is allowed for this server.')
@allowed(['Enabled','Disabled'
])
param publicNetworkAccess string = 'Disabled'

@description('Required. The name of the server.')
param serverName string

@description('Optional.	The name of the sku, typically, tier + family + cores, e.g. B_Gen4_1, GP_Gen5_8.')
param skuName string = 'GP_Gen5_2'

@description('Optional. The source server resource id to restore from. It\'s required when "createMode" is "GeoRestore" or "Replica" or "PointInTimeRestore".')
param sourceServerResourceId string = ''

@description('Optional. Auto grow of storage.')
param enableStorageAutogrow bool = true

@description('Validate input parameter for storageAutogrow')
var validStorageAutogrow = createMode == 'Replica' ? null : (enableStorageAutogrow ? 'Enabled' : 'Disabled')

@description('Optional. The storage size of the server.')
param storageSizeGB int = 32

@description('Optional. The version of the MySQL server.')
@allowed(['5.6', '5.7', '8.0'])
param version string = '8.0'

@description('Array of role assignment objects that contain the "roleDefinitionIdOrName" and "principalId" to define RBAC role assignments on this resource. In the roleDefinitionIdOrName attribute, provide either the display name of the role definition, or its fully qualified ID in the following format: "/providers/Microsoft.Authorization/roleDefinitions/c2f4ef07-c644-48eb-af81-4b1b4947fb11"')
param roleAssignments array = []

var varPrivateEndpoints = [for endpoint in privateEndpoints: {
  name: '${mysqlServer.name}-${endpoint.name}'
  privateLinkServiceId: mysqlServer.id
  groupIds: [
    endpoint.groupId
  ]
  subnetId: endpoint.subnetId
  privateDnsZones: contains(endpoint, 'privateDnsZoneId') ? [
    {
      name: 'default'
      zoneId: endpoint.privateDnsZoneId
    }
  ] : []
  manualApprovalEnabled: contains(endpoint, 'manualApprovalEnabled') ? endpoint.manualApprovalEnabled : false
}]

resource mysqlServer 'Microsoft.DBforMySQL/servers@2017-12-01' = {
  name: serverName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    createMode: createMode
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    version: version
    sslEnforcement: sslEnforcement
    minimalTlsVersion: minimalTlsVersion
    infrastructureEncryption: infrastructureEncryption
    storageProfile: {
      storageMB: storageSizeGB * 1024
      backupRetentionDays: backupRetentionDays
      geoRedundantBackup: geoRedundantBackup
      storageAutogrow: validStorageAutogrow
    }
    publicNetworkAccess: publicNetworkAccess
    sourceServerId: createMode != 'Default' ? sourceServerResourceId : null
    restorePointInTime: createMode == 'PointInTimeRestore' ? restorePointInTime : null
  }
}

@batchSize(1)
resource mysqlServerFirewallRules 'Microsoft.DBforMySQL/servers/firewallRules@2017-12-01' = [for firewallRule in firewallRules: {
  name: firewallRule.name
  parent: mysqlServer
  properties: {
    startIpAddress: firewallRule.startIpAddress
    endIpAddress: firewallRule.endIpAddress
  }
}]

resource mysqlServerVirtualNetworkRules 'Microsoft.DBforMySQL/servers/virtualNetworkRules@2017-12-01' = [for virtualNetworkRule in virtualNetworkRules: {
  name: virtualNetworkRule.name
  properties: {
    ignoreMissingVnetServiceEndpoint: virtualNetworkRule.ignoreMissingVnetServiceEndpoint
    virtualNetworkSubnetId: virtualNetworkRule.virtualNetworkSubnetId
  }
}]

@batchSize(1)
resource mysqlServerDatabases 'Microsoft.DBforMySQL/servers/databases@2017-12-01' = [for database in databases: {
  name: database.name
  parent: mysqlServer

  properties: {
    charset: contains(database, 'charset') ? database.charset : 'utf32'
    collation: contains(database, 'collation') ? database.collation : 'utf32_general_ci'
  }
}]

@batchSize(1)
resource mysqlServerConfig 'Microsoft.DBforMySQL/servers/configurations@2017-12-01' = [for configuration in serverConfigurations: {
  name: configuration.name
  dependsOn: [
    mysqlServerFirewallRules
  ]
  parent: mysqlServer
  properties: {
    value: configuration.value
    source: 'user-override'
  }
}]

@batchSize(1)
module mysqlRbac 'modules/rbac.bicep' = [for (roleAssignment, index) in roleAssignments: {
  name: 'mysql-rbac-${uniqueString(deployment().name, location)}-${index}'
  params: {
    description: contains(roleAssignment, 'description') ? roleAssignment.description : ''
    principalIds: roleAssignment.principalIds
    roleDefinitionIdOrName: roleAssignment.roleDefinitionIdOrName
    principalType: contains(roleAssignment, 'principalType') ? roleAssignment.principalType : ''
    serverName: serverName
  }
}]

module mysqlPrivateEndpoint 'modules/privateEndpoint.bicep' = {
  name: '${serverName}-${uniqueString(deployment().name, location)}-private-endpoints'
  params: {
    location: location
    privateEndpoints: varPrivateEndpoints
    tags: tags
  }
}

// ------ Diagnostics settings ------
type diagnosticSettingsRetentionPolicyType = {
  @description('the number of days for the retention in days. A value of 0 will retain the events indefinitely.')
  days: int
  @description('a value indicating whether the retention policy is enabled.')
  enabled: bool
}

type diagnosticSettingsLogsType = {
  @description('Name of a Diagnostic Log category for a resource type this setting is applied to.')
  category: string?
  @description('Create firewall rule before the virtual network has vnet service endpoint enabled.')
  categoryGroup: string?
  @description('A value indicating whether this log is enabled.')
  enabled: bool
  @description('The retention policy for this log.')
  retentionPolicy: diagnosticSettingsRetentionPolicyType?
}

type diagnosticSettingsMetricsType = {
  @description('Name of a Diagnostic Metric category for a resource type this setting is applied to.')
  category: string?
  @description('A value indicating whether this log is enabled.')
  enabled: bool
  @description('The retention policy for this log.')
  retentionPolicy: diagnosticSettingsRetentionPolicyType?
  @description('the timegrain of the metric in ISO8601 format.')
  timeGrain: string?
}

type diagnosticSettingsEventHubType = {
  @description('The resource Id for the event hub authorization rule.')
  EventHubAuthorizationRuleId: string
  @description('The name of the event hub.')
  EventHubName: string
}

type diagnosticSettingsReceiversType = {
  @description('The settings required to use EventHub.')
  eventHub: diagnosticSettingsEventHubType?
  @description('A string indicating whether the export to Log Analytics should use the default destination type, i.e. AzureDiagnostics, or a target type created as follows: {normalized service identity}_{normalized category name}.')
  logAnalyticsDestinationType: string?
  @description('The full ARM resource ID of the Marketplace resource to which you would like to send Diagnostic Logs.')
  marketplacePartnerId: string?
  @description('The resource ID of the storage account to which you would like to send Diagnostic Logs.')
  storageAccountId: string?
  @description('The full ARM resource ID of the Log Analytics workspace to which you would like to send Diagnostic Logs.')
  workspaceId: string?
}

type diagnosticSettingsPropertiesType = {
  @description('The list of logs settings.')
  logs: diagnosticSettingsLogsType[]?
  @description('The list of metric settings.')
  metrics: diagnosticSettingsMetricsType[]?
  @description('The service bus rule Id of the diagnostic setting. This is here to maintain backwards compatibility.')
  serviceBusRuleId: string?
  @description('Destiantion options.')
  diagnosticReceivers: diagnosticSettingsReceiversType?
}

@description('Provide mysql diagnostic settings properties.')
param diagnosticSettingsProperties diagnosticSettingsPropertiesType = {}

@description('Enable mysql diagnostic settings resource.')
var enableMysqlDiagnosticSettings  = (empty(diagnosticSettingsProperties.?diagnosticReceivers.?workspaceId) && empty(diagnosticSettingsProperties.?diagnosticReceivers.?eventHub) && empty(diagnosticSettingsProperties.?diagnosticReceivers.?storageAccountId) && empty(diagnosticSettingsProperties.?diagnosticReceivers.?marketplacePartnerId)) ? false : true

resource mysqlDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableMysqlDiagnosticSettings) {
  name: '${serverName}-diagnostic-settings'
  properties: {
    eventHubAuthorizationRuleId: diagnosticSettingsProperties.diagnosticReceivers.?eventHub.?EventHubAuthorizationRuleId ?? null
    eventHubName:  diagnosticSettingsProperties.diagnosticReceivers.?eventHub.?EventHubName ?? null
    logAnalyticsDestinationType: diagnosticSettingsProperties.diagnosticReceivers.?logAnalyticsDestinationType ?? null
    logs: diagnosticSettingsProperties.?logs ?? null
    marketplacePartnerId: diagnosticSettingsProperties.diagnosticReceivers.?marketplacePartnerId ?? null
    metrics: diagnosticSettingsProperties.?metrics ?? null
    serviceBusRuleId: diagnosticSettingsProperties.?serviceBusRuleId ?? null
    storageAccountId: diagnosticSettingsProperties.diagnosticReceivers.?storageAccountId ?? null
    workspaceId: diagnosticSettingsProperties.diagnosticReceivers.?workspaceId ?? null
  }
  scope: mysqlServer
}

@description('MySQL Single Server Resource id')
output id string = mysqlServer.id
@description('MySQL Single Server fully Qualified Domain Name')
output fqdn string = mysqlServer.properties.fullyQualifiedDomainName
