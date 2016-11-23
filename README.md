# AzureGlobalConnectionCenter
Azure Global Connection Center is to connect different national clouds that eliminate the friction to migrate different Azure national clouds. It provides scripts that can help to orchestrate the migration process.

Azure Global Connection Center composes of three components:

1. **Playbook**:
Playbook is a step by step guide as well as a troubleshooting wizard to help Business decision makers/IT admins/Solution Architects to fully comprehend the proper procedures to setup services in Azure China as well issues that may come up during the process and how to resolve them with minimum efforts. Regulatory considerations, Azure China technology platform, Azure China partner solution offerings, application and service migration guidance such as design patterns samples and scenario based tips are some of the topics covered in depth.

2. **Assessment Toolkit**:
Assessment Toolkit is a quick and simple tool to generate report and answer "Frequent Asked Question" when migrating Azure Services between different environment like service parity, cost estimation and considerations. It is a PowerShell Module and after install you can start assessment your subscription to make sure the plan and validation of migration.

3. **CICD Toolkit**:
CICD (Continuous Integration Continuous Deliver) Toolkit is a quick and simple tool to validate and perform the actual migration as script base. For example, you can leverage the toolkit to migrate your VMs from East Asia to China East. The toolkit will sync your data and configuration so that everything is as same as original. Moreover, the scripts is opensource so you can just integrate into your own DevOps process to perform CICD between Azure Environments.

![Connection Center](https://globalconnectioncenter.blob.core.windows.net/githubpics/Global%20Connection%20Center%20Diagram.png)
